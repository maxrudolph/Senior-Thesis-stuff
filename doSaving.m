function doSaving(filename,results,data,measure,options,forwardModel,pBounds)
     save(filename,'results','data','options','measure','forwardModel','pBounds','-v7.3');
end
