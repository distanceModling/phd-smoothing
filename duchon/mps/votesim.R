# looking at MPs voting records
library(mdspack)

year<-"1997" # "2005"


# first the lookup table between MP numbers, names, parties and URL
lookup<-read.table(file=paste("votematrix-",year,".txt",sep=""),skip=19,header=T,sep="\t",comment.char="")

# indicator over whether the MP is Labour
labbin<-data.frame(lab=as.numeric(lookup$party=="Lab"),mpid=lookup$mpid)

# 2005
#1302 mps
#1506 divisions
#Data Values

# 1997
#678 mps
#1273 divisions


# load in the vote matrix, rowid, date, voteno, Bill name, then MP codes
votes<-read.delim2(file=paste("votematrix-",year,".dat",sep=""),header=T,quote="",fill=FALSE)

## pull out some other bits of data
# mpid in votes
mpid<-names(votes)[5:(dim(votes)[2]-1)]
mpid<-as.numeric(sub("mpid","",mpid))

# the date of the votes
votedates<-strptime(votes$date,"%Y-%m-%d")

# take transpose of the votes so rows are MPs and columns are divisions
votemat<-t(as.matrix(votes[,5:(dim(votes)[2]-1)]))
attr(votemat,"dimnames")[[2]]<-votes$voteno # put the vote number in
# need to recode:
# missing: -9     => 0
# tellaye: 1      => 1
# aye: 2          => 1
# both: 3         => 0
# no: 4           => -1
# tellno: 5       => -1
votemat[votemat==-9]<-0
votemat[votemat==1]<-1
votemat[votemat==2]<-1
votemat[votemat==3]<-0
votemat[votemat==4]<- -1
votemat[votemat==5]<- -1

# binary var saying whether they were labour or not
mpparty<-labbin$lab[match(mpid,labbin$mpid)]
names(mpparty)<-"lab"

############################################################
# take a sample, fit a model, predict back

samp.size<-100
sim.size<-2#100

library(foreach)
library(doMC)
registerDoMC()
options(cores=2)

result<-foreach(i=1:sim.size,.combine=rbind,.init=c()) %dopar% {

   retvec<-rep(0,length(mpid))

   # create sample and prediction data sets
   samp.ind<-sample(1:dim(votemat)[1],samp.size)
   samp.dat<-votemat[samp.ind,]
   pred.dat<-votemat[-samp.ind,]
   
   
   D.samp<-dist(samp.dat)
   
   mds.dim<-choose.mds.dim(D.samp,0.75)
   
   mds.obj<-cmdscale(D.samp,mds.dim,eig=TRUE,k=mds.dim,x.ret=TRUE)
   samp.mds<-mds.obj$points
   
   samp.mds<-cbind(mpparty[samp.ind],samp.mds)
   attr(samp.mds,"dimnames")[[2]]<-c("lab",letters[(26-(dim(samp.mds)[2]-2)):26])
   attr(samp.mds,"dimnames")[[1]]<-mpid[samp.ind]
   samp.mds<-as.data.frame(samp.mds)
   
   # model setup
   m<-c(2,mds.dim/2-1)
   gam.options<-paste("bs='ds',k=100, m=c(",m[1],",",m[2],")",sep="")
   
   # find the prediction terms
   pred.terms<-letters[(26-(dim(samp.mds)[2]-2)):26]
   pred.terms<-paste(pred.terms,collapse=",")
   
   # create the gam formula
   gam.formula<-paste("lab~s(",paste(pred.terms,collapse=","),",",gam.options,")")
   gam.formula<-as.formula(gam.formula)
   
   # run the model
   b<-gam(gam.formula,data=samp.mds,family=binomial(link="logit"))
   
   
   # predictions
   
   # map the predictions
   # using code from insert.mds
   lambda.inverse<-diag(1/mds.obj$eig[1:dim(mds.obj$points)[2]])
   new.dist<-as.matrix(dist(votemat))[samp.ind,]
   new.dist<-new.dist[,-samp.ind]
   S<- -1/2*mds.obj$x
   d<- -(new.dist^2-diag(S))
   pred.mds<-t(1/2*(lambda.inverse %*% t(mds.obj$points) %*% d))
   attr(pred.mds,"dimnames")[[2]]<-letters[(26-(dim(samp.mds)[2]-2)):26]
   
   # predict back over _all_ MPs
   pred.grid<-matrix(NA,length(mpid),mds.dim)
   pred.grid[samp.ind,]<-mds.obj$points
   pred.grid[-samp.ind,]<-pred.mds
   pred.grid<-as.data.frame(pred.grid)
   attr(pred.grid,"names")<-letters[(26-(dim(samp.mds)[2]-2)):26]
   
   pr<-predict(b,pred.grid,type="response")
   
   pr[pr<=0.5]<-0
   pr[pr>0.5]<-1
   
   # mse
   ds.mse<-sum((pr-mpparty)^2)
   
   wrong<-mpid[(t(t(pr))-mpparty)!=0]
   wrong.ind<-match(wrong,lookup$mpid)

   
   # return vector, put 1s where we messed up
   retvec[wrong.ind]<-1

   return(retvec)

#   wrong.names<-paste(lookup$firstname[wrong.ind],lookup$surname[wrong.ind])  
#   cat(wrong.names,sep="\n")
}

#######################################################
## how does the LASSO do?
#
#library(lars)
##la<-lars(samp.dat,mpparty[samp.ind],type="lasso", trace=FALSE, intercept=TRUE,use.Gram=FALSE)
#lasso.cv <- cv.lars(samp.dat, mpparty[samp.ind], plot.it = FALSE,type="lasso", trace=FALSE, intercept=TRUE,use.Gram=FALSE)
#
#fraction.cv <- lasso.cv$fraction[ order(lasso.cv$cv)[1] ]
#
#
#
#lap<-predict(la,pred.dat,s=9,type="fit")
#
#
#la.mse<-sum((lap$fit-mpparty[-samp.ind])^2)
#
#
#
#
#cat("LASSO MSE=",la.mse,"\n")
#cat("Duchon MSE=",ds.mse,"\n")



# save time
save.image("mps-results.RData")


