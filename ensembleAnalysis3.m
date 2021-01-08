%function ensembleAnalysis(filename)
rng(1); %reproducibility
disp('Loading data...')
load(filename,'data','forwardModel','results','measure','pBounds')
saveFigures = false;
%% Section 1 NF: evaluate ensemble solutions on regularly spaced grid
disp('Evaluating ensemble...');
minDistL = log10(measure.minDist);
maxDistL = log10(measure.maxDist);
nxplot=200; %number of measurement points
nSavedPlot = 2000; %Number of saved runs to plot
if nSavedPlot > size(results.ensembleRhos,2)
    %If low # of saved runs, plot all, otherwise...
    nSavedPlot = size(results.ensembleRhos,2);
    runPlotIndex = 1:nSavedPlot;
else %... only plot a random subset of them
    runPlotIndex = randperm(size(results.ensembleRhos,2),nSavedPlot);
end
yVals = zeros(nxplot,nSavedPlot);
xVals = logspace(minDistL,maxDistL,nxplot)';
lambdaForXVals = makeLambda(xVals);

for i=1:nSavedPlot
    yVals(:,i) = forwardModel(squeeze(results.ensembleDepths(:,runPlotIndex(i))),...
        results.ensembleRhos(:,runPlotIndex(i)),lambdaForXVals);
end

%% Section 2 NF: Calculating other models
disp('Calculating models...');
%Calculated mean and calculated median
%Both calculated in log space, from the entire ensemble
nzplot = 500;
zVals = 10.^linspace(log10(pBounds.depthMin),log10(pBounds.depthMax),nzplot)';
numSavedRuns = size(results.ensembleRhos,2);
depthPlot = repmat(zVals,1,numSavedRuns);
logDepthPlot = log10(depthPlot);
rhoPlot = zeros(size(depthPlot));
for i = 1:numSavedRuns %for each run...
    nLayer = nnz(~isnan(results.ensembleDepths(:,i)));
    %...Find the number of layers in that run...
    for j = 1:nLayer
        mask = zVals >= results.ensembleDepths(j,i);
        rhoPlot(mask,i) = results.ensembleRhos(j,i);
    end
end
logRhoPlot = log10(rhoPlot);

inRhos = 10.^(mean(logRhoPlot,2));
mMean = calculatedModel(zVals,inRhos,forwardModel(zVals,inRhos,...
    data.lambda),data.y,'g','-','Model Space Mean');
inRhos = 10.^(median(logRhoPlot,2));
mMedian = calculatedModel(zVals,inRhos,forwardModel(zVals,inRhos,...
    data.lambda),data.y,'y','-','Model Space Median');

% Ensemble median and best fit models
[~,ind2] = sort(results.ensembleMisfits);
medianIndex= ind2(floor(length(ind2)/2));
bestIndex = ind2(1);
medianRhoPlot = zeros(size(zVals,1),1);
bestRhoPlot = zeros(size(zVals,1),1);
for j = 1:size(results.ensembleDepths,1)
    mask = zVals >= results.ensembleDepths(j,medianIndex);
    medianRhoPlot(mask) = results.ensembleRhos(j,medianIndex);
    mask = zVals >= results.ensembleDepths(j,bestIndex);
    bestRhoPlot(mask) = results.ensembleRhos(j,bestIndex);
end

inRhos = medianRhoPlot;
dMedian = calculatedModel(zVals,inRhos,forwardModel(zVals,inRhos,...
    data.lambda),data.y,'k','-','Data Space Median');
inRhos = bestRhoPlot;
bestFit = calculatedModel(zVals,inRhos,forwardModel(zVals,inRhos,...
    data.lambda),data.y,'c','-','Best Fit Model');
%Maximum likelihood model
% compute a bivariate histogram of resitvity values from the posterior ensemble
numBins = 2*nxplot;
[numElements,binCenters]=hist3([logRhoPlot(:),logDepthPlot(:)],...
    {linspace(-10,10,numBins) log10(zVals)},'CDataMode','auto');
% First linspace is for log(rho), second is for log(depth)
% at each depth, find the most likely solution (ml_rho)
maxLikelihoodRho = zeros(nzplot,1);
ksRho = linspace(log10(pBounds.rhoMin),log10(pBounds.rhoMax),1e4);
%Bandwidth issues - possible bug in matlab
logRhoPlot = logRhoPlot';
parfor i=1:nzplot
    % Use ksdensity to approximate the pdf of resistivity at this depth:
    [pdfYVals,pdfXVals] = ksdensity(logRhoPlot(:,i),ksRho,'bandwidth',.05);
    [~,ind1] = max(pdfYVals);
    maxLikelihoodRho(i) = 10.^pdfXVals(ind1);
end
logRhoPlot = logRhoPlot';
inRhos = maxLikelihoodRho;
maxLikelihood = calculatedModel(zVals,inRhos,forwardModel(zVals,inRhos,...
    data.lambda),data.y,'m','-','Maximum Likelihood Model');

%Setup true model
[trueDepths,trueRhos] = modelGen(measure.kMax,measure.modelChoice);
trueLogDepthsPlot = logDepthPlot(:,1);
trueLogRhoPlot = zeros(nzplot,1);
trueNumLayers = nnz(~isnan(trueDepths));
for j = 1:trueNumLayers
    mask = log10(zVals) >= log10(trueDepths(j));
    trueLogRhoPlot(mask) = log10(trueRhos(j));
end
inDepths = 10.^trueLogDepthsPlot;
inRhos = 10.^trueLogRhoPlot;
trueModel = calculatedModel(inDepths,inRhos,forwardModel(inDepths,inRhos,...
    data.lambda),data.y,'r','-','True Model');

%% 3 Figures
disp('Plotting properties...');
smallPlots(results);
%% Section 4 The big figure:
disp('More plots...');
allModels = {trueModel,mMean,mMedian,bestFit,maxLikelihood,dMedian};

bigPlot(binCenters,numElements,allModels,xVals,yVals,data,results,' ');
%% 5 Clustering stuff
disp('Calculating number of clusters')
%downsample
downsample = false;
if downsample
    downsampleNumber = floor(size(results.ensembleRhos,2)/10);
    gmPlotIndex = randperm(size(results.ensembleRhos,2),downsampleNumber);
else
    downsampleNumber = size(results.ensembleRhos,2);
    gmPlotIndex = 1:size(results.ensembleRhos,2);
end

%Use k-means clustering
maxNumClusters = 6;
clust = zeros(downsampleNumber,maxNumClusters);
dsLogRhoPlot = logRhoPlot(:,gmPlotIndex);
parfor i = 1:maxNumClusters
    fprintf('\nCalculating for %d clusters',i)
    clust(:,i) = kmeans(dsLogRhoPlot',i);
end

%Step 2: Use results from k-means to determine optimal # of clusters
eva = evalclusters(dsLogRhoPlot',clust,'CalinskiHarabasz');
numClusters = eva.OptimalK;

%Step 3: Find Gaussian mixture models
disp('Finding Gaussian models')
options = statset('Display','final');
GMModel = fitgmdist(dsLogRhoPlot',numClusters,'Options',options,...
    'RegularizationValue',1e-8);

%Step 4: Find kmeans centroids
disp('Finding k-means')
[idxEuclid,CEuclid,sumdEuclid] = kmeans(dsLogRhoPlot',numClusters);
[idxMan,CMan,sumdMan] = kmeans(dsLogRhoPlot',numClusters,'Distance','cityblock');

%Step 5: Hierarchical
disp('Hierarchical clustering')
T = clusterdata(dsLogRhoPlot','MaxClust',numClusters);

%Step 5: Make models
disp('Calculating models')
GMData = cell(1,numClusters+1);
KMDataEuclid = cell(1,numClusters+1);
KMDataMan = cell(1,numClusters+1);
GMData{1} = trueModel;
KMDataEuclid{1} = trueModel;
KMDataMan{1} = trueModel;
for i = 1:numClusters
    inRhos = 10.^GMModel.mu(i,:)';
    GMData{i+1} = calculatedModel(zVals,inRhos,forwardModel(zVals,inRhos,...
        data.lambda),data.y,rand(1,3),'--',strcat('GM mean #',num2str(i)));
    inRhos = 10.^CEuclid(i,:)';
    KMDataEuclid{i+1} = calculatedModel(zVals,inRhos,forwardModel(zVals,...
        inRhos,data.lambda),data.y,rand(1,3),'--',strcat('Centroid #',...
        num2str(i)));
    inRhos = 10.^CMan(i,:)';
    KMDataMan{i+1} = calculatedModel(zVals,inRhos,forwardModel(zVals,...
        inRhos,data.lambda),data.y,rand(1,3),'--',strcat('Centroid #',...
        num2str(i)));
end

%%6 Plots of GM and k-means
disp('Plotting')

bigPlot(binCenters,numElements,GMData,xVals,yVals,data,results,...
    'Gaussian Mixture Models')
bigPlot(binCenters,numElements,KMDataEuclid,xVals,yVals,data,results,...
    'K-means: Euclidean');
kMeansPlots('K-means: Euclidean',idxEuclid,sumdEuclid,KMDataEuclid);
bigPlot(binCenters,numElements,KMDataMan,xVals,yVals,data,results,...
    'K-means: Manhattan');
kMeansPlots('K-means: Manhattan',idxMan,sumdMan,KMDataMan);

%% 7 Optional: Save ensemble for The Sequencer
% nsequence = 100000;
% slashpos = find(filename=='/',1,'last');
% txtfile = [filename(slashpos+1:end-3) 'csv'];
% % each row should correspond to a different resistivity profile
% csvwrite(txtfile,logRhoPlot(:,end-nsequence:end)'); % note that sequencer
% struggles with very large datasets. I choose just the last nsequence
% samples in the ensemble.

%% 8 Optional: save the figure
% export_fig([results_file(1:end-4) '_ensemble.eps'])
%exportgraphics(gcf,[results_file(1:end-4) '_ensemble.eps'],'ContentType','vector');

%end
%% Functions

function bigPlot(bC,nE,inModels,x,y,data,results,inTitle)
figure;
title(inTitle);
subplot(4,2,[2 4 6 8]);
modelSpacePlot(bC,nE,inModels,'Model Space');

%Part 2: Data space plot
subplot(4,2,[3 5 7]);
dataSpacePlot(x,y,inModels,data);

% Part 3 Sub-figure: Histogram of misfit in data space
subplot(4,2,1);
plotMisfit(inModels,results);
end

function kMeansPlots(intitle,idx,sumd,inModels)
numClusters = size(inModels,2)-1;
figure();
title(intitle)
subplot(3,1,1);
histogram(idx);
%set(gca,'YScale','log');
title('Number of ensemble slns');
xlabel('Cluster #');
ylabel('Frequency');

averageDist = zeros(1,numClusters);
centroidMisfits = zeros(1,numClusters);
for i = 1:numClusters
    averageDist(i) = sumd(i)/nnz(idx==i);
    centroidMisfits = inModels{i+1}.misfit;
end

subplot(3,1,2);
bar(averageDist);
title('Distance from Centroid ');
ylabel('Log-distance');
xlabel('Cluster');

subplot(3,1,3);
bar(centroidMisfits)
title('Misfit')
ylabel('Data-space misfit (m)')
xlabel('Cluster');
end

function modelSpacePlot(bC,nE,inModels,inTitle)
pcolor(10.^bC{1},10.^bC{2},nE'); shading flat;
set(gca,'XScale','log','YScale','log');
hold on
for i = 1:size(inModels,2)
    plot(inModels{i}.rhos,inModels{i}.depths,'LineStyle',...
        inModels{i}.lineStyle,'Color',inModels{i}.color,'DisplayName',...
        inModels{i}.displayName);
end
colorbar();
legend();
set(gca,'YDir','reverse');
set(gca,'FontSize',12);
set(gca,'Box','on');
xlabel('Resistivity (\Omega-m)');
ylabel('Depth (m)');
legend()
title(inTitle)
end

function dataSpacePlot(x,y,inModels,data)
hold on;
ensembleColor = [200 200 200]/255;

%Ensemble solution
for i=1:size(y,2)
    plot(x,y(:,i),'Color',ensembleColor);
end

set(gca,'Box','on');
set(gcf,'Color','w');
for i = 1:size(inModels,2)
    loglog(data.x,inModels{i}.y,'Color',inModels{i}.color,'LineStyle',...
        inModels{i}.lineStyle);
end
loglog(data.x,data.y,'.','Color',inModels{1}.color,'MarkerSize',10.0);
loglog(x,mean(y,2),'b');

set(gca,'FontSize',12);
set(gca,'Color','w');
set(gca,'XScale','log','YScale','log');
xlabel('Array Spacing (m)');
ylabel('Apparent Resistivity (\Omega-m)')
end

function plotMisfit(inModels,results)
histogram(results.ensembleMisfits,100);
hold on;
yy=get(gca,'YLim');
for iPlot = 1:size(inModels,2)
    plot(inModels{iPlot}.misfit*[1 1],yy,'LineStyle',inModels{iPlot}.lineStyle,...
        'Color',inModels{iPlot}.color);
end
set(gca,'FontSize',12);
xlabel('Misfit (m)');
end

%{
%% AIC and BIC vs regularization value
disp('testing phase...');
rng(1);
%downsample
downsampleNumber = floor(size(results.ensembleRhos,2)/10);
gmPlotIndex = randperm(size(results.ensembleRhos,2),downsampleNumber);

%Step one: use k-means clustering
numClusters = 6;
clust = zeros(downsampleNumber,numClusters);
gmRhoPlot = logRhoPlot(:,gmPlotIndex);
parfor i=1:numClusters
    disp(i);
    clust(:,i) = kmeans(gmRhoPlot',i);
end

AIC = zeros(1,10);
BIC = zeros(1,10);

for iReg = 1:10
    eva = evalclusters(gmRhoPlot',clust,'CalinskiHarabasz');
    options = statset('Display','final');
    GMModel = fitgmdist(gmRhoPlot',eva.OptimalK,...
        'Options',options,'RegularizationValue',1*(10^(-iReg)));
    AIC(iReg) = GMModel.AIC;
    BIC(iReg) = GMModel.BIC;
    disp(iReg)
end

figure;
plot([1:10],AIC,'*','DisplayName','AIC');
hold on
plot([1:10],BIC,'^','DisplayName','BIC');
xlabel('Regularization Value = 1e(-x)')
ylabel('AIC or BIC');
legend;
%% Figure of model-space vs data-space misfit
allModelSpaceMisfits = zeros(numSavedRuns,1);
for i = 1:numSavedRuns
    allModelSpaceMisfits(i) = norm(logRhoPlot(:,i)-...
        log10(interpolatedTrueRhos'))/norm(log10(interpolatedTrueRhos'));
end
allDataSpaceMisfits = results.ensembleMisfits/norm(data.y);
figure,plot(allModelSpaceMisfits,allDataSpaceMisfits,'.')
xlabel('Model Space Misfit')
ylabel('Data Space Misfit')
figure
hold on
[~,ind] = sort(allModelSpaceMisfits);
for i = 1:10
    plot(logRhoPlot(:,ind(end-i+1)))
    plot(logRhoPlot(:,ind(i)),'--')
end
%}