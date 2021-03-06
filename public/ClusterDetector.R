# Election Forensics Toolkit
# by Kirill Kalinin and Walter R. Mebane, Jr.
# 25sep2015

# run local Getis-Ord and Moran's I statistics with permutation inferences

library(doParallel)
usecores <- 30;

library(foreign) 
library(maptools)
library(spdep)
library(RANN)
library(foreach)

#library("Biobase")
#require("Biobase")
ClusterDetector<-function(dataCL=dataCL, IndexCL=IndexCL, candidatesCL=candidatesCL, methodsCL=methodsCL){
asc <- function(z) { as.character(z) }

fdr1 <- function(p, level=.05) {
  lenp <- length(p);
  test <- (1:lenp)/lenp*level > sort(p);
  nrejects <- sum(test);
  if (nrejects > 0) {
    oop <- order(order(p));
    pickrejects <- (1:lenp)[test[oop]];
    idx <- 1:max((1:lenp)[test]);
    nrejects <- length(idx);
    rejects <- sort(p)[idx];
  }
  else {
    pickrejects <- idx <- rejects <- NULL;
  }
  list(ntests=lenp, nrejects=nrejects, rejects=rejects,
       pickrejects=pickrejects);
}

coltable <- matrix(NA,5,3);
dimnames(coltable) <- list(c("LL","HH","LH","HL","ns"),c("99","95","90"));
coltable["LL",] <- c("#0000FF","#B4B4FF","#E6E6E6"); # blue
coltable["HH",] <- c("#FF0000","#FFB4B4","#E6E6E6"); # red
coltable["LH",] <- c("#32CD32","#C8FFC8","#E6E6E6"); # green
coltable["HL",] <- c("#FF9900","#FFFFB4","#E6E6E6"); # orange
coltable["ns",] <- c("#E6E6E6","#E6E6E6","#E6E6E6");
#coltable["LL",] <- c("#0000FF","#6464FF","#B4B4FF");
#coltable["HH",] <- c("#FF0000","#FF6464","#FFB4B4");
#coltable["LH",] <- c("#00FF00","#64FF64","#B4FFB4");
#coltable["HL",] <- c("#FFFF00","#FFFF64","#FFFFB4");
#coltable["ns",] <- c("#E6E6E6","#E6E6E6","#E6E6E6");

permuteStart <- function(j,wshp,X,w,k,longlat) {
  x <- X[,j];
  x <- ifelse(x<0,NA,x);
  if (any(is.na(x))) {
    locm <- (1:length(x))[is.na(x)];
    wshpj <- wshp[-locm,];
    comatj <- coordinates(wshpj);
    NNj <- knearneigh(comatj, k=k, longlat=longlat);
    wj <- nb2listw(knn2nb(NNj),style="B");
    xj <- x[-locm];
    mj <- localmoran(xj, wj, zero.policy=FALSE);
    gj <- localG(xj, wj, zero.policy=FALSE);
    m <- matrix(NA,length(x),5);
    dimnames(m)[[2]] <- dimnames(mj)[[2]];
    attr(m,"class") <- attr(mj,"class");
    attr(m,"call") <- attr(mj,"call");
    m[-locm,] <- mj;
    g <- rep(NA,length(x));
    attr(g,"class") <- attr(gj,"class");
    attr(g,"call") <- attr(gj,"call");
    attr(g,"gstarti") <- attr(gj,"gstarti");
    g[-locm] <- gj;
  }
  else {
    NNj <- NULL;
    m <- localmoran(x, w, zero.policy=FALSE);
    g <- localG(x, w, zero.policy=FALSE);
  }
  list(m=m, g=g, NN=NNj);
}


permuteIter <- function(n,X,NN,NNlist) {
  s <- sample(n);
  NNs <- t(sapply(1:n,function(k){ s[NN[[1]][k,]]; }));
  loc <- sapply(1:n, function(k){ match(k,NNs[k,]); });
  for (ii in (1:n)[!is.na(loc)]) {
    NNs[ii,loc[!is.na(loc)][ii]] <- sample(s[!(s %in% NNs[ii,])],1);
  }
  NNi <- NN;
  NNi[[1]] <- NNs;
  wi <- nb2listw(knn2nb(NNi),style="B");
  J <- dim(X)[2];
  Garr <- Iarr <- array(NA,dim=c(J,n));
  for (j in 1:J) {
    x <- X[,j];
    x <- ifelse(x<0,NA,x);
    if (any(is.na(x))) {
      locm <- (1:length(x))[is.na(x)];
      xj <- x[-locm];
      NNj <- NNlist[[j]];
      sj <- sample(nj <- dim(NNj[[1]])[1]);
      NNjs <- t(sapply(1:nj,function(k){ sj[NNj[[1]][k,]]; }));
      locj <- sapply(1:nj, function(k){ match(k,NNjs[k,]); });
      for (ii in (1:nj)[!is.na(locj)]) {
        NNjs[ii,locj[!is.na(locj)][ii]] <- sample(sj[!(sj %in% NNjs[ii,])],1);
      }
      NNj[[1]] <- NNjs;
      wj <- nb2listw(knn2nb(NNj),style="B");
      Iarr[j,-locm] <- localmoran(xj, wj, zero.policy=FALSE)[,"Ii"];
      Garr[j,-locm] <- localG(xj, wj, zero.policy=FALSE);
    }
    else {
      Iarr[j,] <- localmoran(x, wi, zero.policy=FALSE)[,"Ii"];
      Garr[j,] <- localG(x, wi, zero.policy=FALSE);
    }
  }
  list(Iarr=Iarr, Garr=Garr);
}


permutePost <- function(j,n,R,mglist,Iarr,Garr) {
  simg <- simp <- rep(NA,n);
  for (i in 1:n) {
    lo <- sum(mglist[[j]]$m[i,1] < Iarr[j,i,], na.rm=TRUE);
    hi <- sum(mglist[[j]]$m[i,1] > Iarr[j,i,], na.rm=TRUE);
    if (all(is.na(Iarr[j,i,]))) { lo <- hi <- 1; }
    simp[i] <- min(lo,hi)/R;
    lo <- sum(mglist[[j]]$g[i] < Garr[j,i,], na.rm=TRUE);
    hi <- sum(mglist[[j]]$g[i] > Garr[j,i,], na.rm=TRUE);
    if (all(is.na(Garr[j,i,]))) { lo <- hi <- 1; }
    simg[i] <- min(lo,hi)/R;
  }
  list(mglistM=mglist[[j]]$m, simM=simp, mglistG=mglist[[j]]$g, simG=simg);
}

permuteMG <- function(X, NN, wshp, R=1000, k=8, longlat=TRUE) {
  w <- nb2listw(knn2nb(NN),style="B");
  J <- dim(X)[2];
 # browser()
  NNlist <- list();
  registerDoParallel(cores=usecores);
  #browser()
  mglist <- foreach(j=1:J,   .export="permuteStart", .packages=c("spdep", "Matrix")) %dopar% permuteStart(j,wshp,X,w,k,longlat);#c("permuteStart", "localmoran")
  stopImplicitCluster();
  for (j in 1:J) {
    NNlist[[j]] <- mglist[[j]]$NN;
    mglist[[j]]$NN <- list(NULL);
  }
  
  n <- dim(X)[1];
  registerDoParallel(cores=usecores);
 # browser()
  GIlist <- foreach(i=1:R, .export="permuteIter", .packages=c("spdep", "Matrix")) %dopar% permuteIter(n,X,NN,NNlist);
  stopImplicitCluster();
  Garr <- Iarr <- array(NA,dim=c(J,dim(X)[1],R));
  for (i in 1:R) {
    Garr[,,i] <- GIlist[[i]]$Garr;
    Iarr[,,i] <- GIlist[[i]]$Iarr;
  }
  registerDoParallel(cores=usecores);
  mgRlist <- foreach(j=1:J, .export="permutePost", .packages=c("Matrix")) %dopar% permutePost(j,n,R,mglist,Iarr,Garr);
  stopImplicitCluster();
  mgRlist;
}


dolocalIter <- function(j,X,NN,pMG) {
  x <- X[,j];
  x <- ifelse(x<0,NA,x);
  xm <- x-mean(x,na.rm=TRUE);
  Wx <- sapply(1:length(xm), function(i){ sum(xm[NN$nn[i,]],na.rm=TRUE) });
  widx <- Wx>0;
  rawtype <- ifelse(xm>0,ifelse(widx,"HH","HL"),ifelse(widx,"LH","LL"));
  zp <- pMG[[j]][["simM"]];
  f99 <- fdr1(zp, level=.01)$pickrejects;
  f95 <- fdr1(zp, level=.05)$pickrejects;
  f90 <- fdr1(zp, level=.1)$pickrejects;
  if (length(f95)>0) f90 <- f90[!(f90 %in% f95)];
  if (length(f99)>0) f95 <- f95[!(f95 %in% f99)];
  msig <- rep(0,length(x));
  msig[f99] <- 3;
  msig[f95] <- 2;
  msig[f90] <- 1;
  type <- ifelse(msig>0,rawtype,"");

  g <- pMG[[j]][["mglistG"]];
  zp <- pMG[[j]][["simG"]];
  f99 <- fdr1(zp, level=.01)$pickrejects;
  f95 <- fdr1(zp, level=.05)$pickrejects;
  f90 <- fdr1(zp, level=.1)$pickrejects;
  if (length(f95)>0) f90 <- f90[!(f90 %in% f95)];
  if (length(f99)>0) f95 <- f95[!(f95 %in% f99)];
  gsign <- ifelse(g>0,1,ifelse(g<0,-1,0));
  sig <- rep(0,length(g));
  sig[f99] <- ifelse(gsign[f99]==1,3,-3);
  sig[f95] <- ifelse(gsign[f95]==1,2,-2);
  sig[f90] <- ifelse(gsign[f90]==1,1,-1);

  list(localm=pMG[[j]][["mglistM"]],msig=msig,type=type,
    localg=pMG[[j]][["mglistG"]],gsig=sig,pMG=pMG[[j]]);
}

dolocal <- function(X, comat, k, wshp, R=1000, ll=TRUE) {
  NN <- knearneigh(comat, k=k, longlat=ll);
  pMG <- permuteMG(X, NN, wshp, R=R, k=k, longlat=ll);
  J <- dim(X)[2];
  registerDoParallel(cores=usecores);
  outlist <- foreach(j=1:J,  .export="dolocalIter") %dopar% dolocalIter(j,X,NN,pMG);
  stopImplicitCluster();
  outlist;
}

plocalM <- function(poshp, localobj) {
  # for local Moran's I
  z <- localobj$localm[,5];
  msig <- localobj$msig;
  sig <- rep("90",length(z));
  sig[msig==1] <- "90";
  sig[msig==2] <- "95";
  sig[msig==3] <- "99";
  COtype <- localobj$type;
  COtype <- ifelse(COtype=="","ns",as.character(COtype));
  COtype <- ifelse(is.na(COtype),"ns",COtype);
  pcolor <- sapply(1:length(sig),function(i){ coltable[COtype[i],sig[i]]; });
  oz <- order(abs(z),decreasing=FALSE);
#  list(pshp=poshp[oz,], pcol=pcolor[oz]);
  list(poshpZ=poshp[oz,], pcolorZ=pcolor[oz]);
}

plocalG <- function(poshp, localobj) {
  # for Getis-Ord
  z <- localobj$localg;
  sig <- localobj$gsig;
  pcolor <-
    ifelse(sig==(-3),"#0000FF",
      ifelse(sig==(-2),"#2791C3",
        ifelse(sig==(-1),"#CAE1FF",
          ifelse(sig==(3),"#FF0000",
            ifelse(sig==(2),"#D08B6C",
              ifelse(sig==(1),"#FFAEB9","#E6E6E6"))))));
  oz <- order(abs(z),decreasing=FALSE);
#  list(pshp=poshp[oz,], pcol=pcolor[oz]);
  list(poshpZ=poshp[oz,], pcolorZ=pcolor[oz]);
}

mkpdf <- function(vnames,pdfname,wshp,wshpplot, ll=TRUE) {
  varID <- rep(NA,length(vnames));
  for (j in 1:length(vnames)) {
    varID[j] <-
      digest::digest(as.character(wshp@data[,vnames[j]]), algo="sha1", serialize=FALSE);
  }
  comat <- coordinates(wshp);
  dimnames(comat)[[2]] <- c("long","lati");
  moutlist <- dolocal(wshp@data[,vnames,drop=FALSE], comat, 8, wshp, ll=ll);
  GraphStorage<-""
  for (j in 1:length(vnames)) {
    gr1 <- plocalM(wshpplot, moutlist[[j]]);
    gr2 <- plocalG(wshpplot, moutlist[[j]]);
    CandName<-vnames[j]  
    GraphStorage<-c(GraphStorage,list(CandName=CandName, list(gr1=gr1,gr2=gr2)))
  }
#  moutlist;
  return(GraphStorage);
}

  methodsCL<-as.numeric(methodsCL)
  methodsDecoded<-c("1","2","L", "05", "05p")
  methodsSelected<-methodsDecoded[methodsCL]
  Candidates_methods<-paste(rep(candidatesCL,each=length(methodsCL)),methodsSelected, sep="_")

#browser()
#get(eval(paste("ShpPoin$",IndexCL,sep="")))

#assign(BashkiaKom, ShpPoin[,which(names(ShpPoin)%in%IndexCL)])
       
#       ShpPoin[,which(names(ShpPoin)%in%IndexCL)]
#       ShpPoin[,which(names(ShpPoin)%in%IndexCL)]
#       ShpPoly[,which(names(ShpPoly)%in%IndexCL)]
#       assign(In, Scalor[[i]])} #Scal
#    loc2 <- match(asc(ShpPoin[,which(names(ShpPoin)%in%IndexCL)]),asc(ShpPoly[,which(names(ShpPoly)%in%IndexCL)]));

#browser()

  pdfbase<-names(dataCL)[1]
  MapsResultsCl <- list();

  if(length(dataCL)==4){
    ShpPoin<-dataCL[[1]]
    ShpPoly<-dataCL[[2]]
    DBFPoin<-dataCL[[3]]
    DBFPoly<-dataCL[[4]]
    loc <- match(asc(ShpPoin@data[,which(names(ShpPoin)%in%IndexCL)]),
      asc(ShpPoly@data[,which(names(ShpPoly)%in%IndexCL)]));
    ShpPoly <- ShpPoly[loc,]
    idx <- sapply(Candidates_methods, function(v){ var(DBFPoin[,v],na.rm=TRUE) })>0;
    if (any(idx)) {
      MapsResultsCl <- mkpdf(Candidates_methods[idx], pdfbase,ShpPoin,ShpPoly, ll=NULL); 
    }
  }

  if(length(dataCL)==2){
    ShpData<-dataCL[[1]]
    DBFData<-dataCL[[2]]
    #if("polygons" %in% slotNames(ShpData))
    #names(ShpData)%in%IndexCL
    idx <- sapply(Candidates_methods, function(v){ var(DBFData[,v],na.rm=TRUE) })>0;
    if (any(idx)) {
      MapsResultsCl <- mkpdf(Candidates_methods, pdfbase,ShpData,ShpData, ll=NULL); 
    }
  }
MapsResultsCl[[1]] <- NULL

return(MapsResultsCl)}
