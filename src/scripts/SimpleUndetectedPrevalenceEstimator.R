# __________________________________
#
# Simple Undetected Prevalence Estimator
#
# AUTHOR: Georgianna Silveira
# ERROR HANDLING: Brenda Hanley
# MODEL LOGGING: Brenda Hanley
# QAQC: Brenda Hanley
#
# Location: Cornell Wildlife Health Laboratory
# License: MIT
#
# This code was originally written by Dr. James Booth at Cornell University
# to estimate the upper bounds of CWD prevalence in deer populations based on 
# two input values: population size (N) and number of negative CWD tests 
# (n). The functions are used to calculate the upper bounds using three 
# estimation methods: Bayesian, Frequentist, and Frequentist including 
# an estimate of sensitivity.
#
# This code was written under:
# R version 4.4.0 (2024-04-24 ucrt) -- "Puppy Cup"
# Copyright (C) 2024 The R Foundation for Statistical Computing
# Platform: x86_64-w64-mingw32/x64
#
#_______________________________________________________________________________

# Load packages. ----------
library(VGAM)
library(tidyverse)

# Reusable Functions
add_item_to_json_array=function(file_path, new_item) {
    # This is a bespoke function that adds a string representing a JavaScript
    # Object to the attachments.json file containing an array listing the model
    # outputs. Although this function has error handling for a missing file and
    # improperly formed file, the existence of the file and a list enclosed in
    # brackets in that file are expected.

    # Check if the file exists.
    if (!file.exists(file_path)) {
        # Write to error log and exit script with an error.
        line=paste0("<h4>ERROR</h4><p>Error: File '", file_path, "' not found.</p>")
        write(line,file=model_log_filepath,append=TRUE)
        quit(status=1)}

    # Read the file content.
    file_content=readChar(file_path, file.info(file_path)$size)

    # Check if the file is empty.
    if (nchar(file_content) == 0) {
        line=paste0("<h4>ERROR</h4><p>Error: File '", file_path, "' is empty.</p>")
        write(line,file=model_log_filepath,append=TRUE)
        quit(status=1)}

    # Remove the last closing bracket.
    file_content=substr(file_content, 1, nchar(file_content) - 1)

    # Create a function for adding double quotes around text.
    double_quote=function(x) {paste0('"', x, '"')}

    # Create the new item as a JSON string using shQuote with double_quote.
    new_item_json=paste0(
        "{",
        paste(
            sapply(names(new_item), double_quote),
            sapply(as.character(new_item), double_quote),
            sep=":", collapse=","
        ),
        "}"
    )

    # Add comma, new item, and closing bracket to the file content
    file_content=paste0(file_content, ",", new_item_json, "]")

    # Write the updated data back to the file
    writeLines(file_content, file_path, sep="")
}

# Info about Required Data. ------------
# There are four required files that will always be imported:
# 1. A csv file of parameters (to get alpha and Sens).
# 2. A csv file of sample data (to get n).
# 3. A csv file of sub-administrative areas (to get the standard data frame). 
# 4. A csv file of demography data (to get N).

# Model log file started with Python data processing script. -------
model_log_filepath=file.path("","data","attachments","info.html")

# Continue the log started with the python script. ----------
line='<h4>Model Execution</h4>'
write(line,file=model_log_filepath,append=TRUE)

# Read in the (Required) Parameters file. -----------
params_filepath=file.path("","data","params.csv")
params=readr::read_csv(params_filepath)
# Note: The params.csv has to exist b/c Python generated it and b/c model has 
# to create it. Therefore,this error handling is in the python code and this 
# R script will not run if it does not exist.

    # Make sure the names are consistent. 
    colnames(params)=c("alpha","sensitivity")

    # Obtain the parameters from the params file.
    confidence=1-as.numeric(params$alpha) # Confidence level.
    Sens=as.numeric(params$sensitivity) # Sensitivity of the diagnostic test.

# Read in the (Required) SubAdmin file. --------- 
subadmin_filepath=file.path("","data","sub_administrative_area.csv")
subadmin=readr::read_csv(subadmin_filepath) 
# Note: The sub_administrative_area.csv has to exist b/c Python generated it 
# and b/c model has to create it. Therefore, this error handling is in the 
# python code and this R script will not run if it does not exist. 

    # Make sure the names are consistent. 
    colnames(subadmin)=c("SubAdminID","FullName","Name","Area")

# Read in (Required) Samples file. -----------
sample_filepath=file.path("","data","sample.csv")
sample=readr::read_csv(sample_filepath) 
# Note: The samples.csv has to exist b/c Python generated it 
# and b/c model has to create it. Therefore, this error handling is in the 
# python code and this R script will not run if it does not exist.

    # Make sure the names are consistent. 
    colnames(sample)=c("ID","Species","Source","SeasonYear","Age","Sex","Result","SubAdminID")

# Read in (Required) Demography file. ----------
demography_filepath=file.path("","data","demography.csv")
demography=readr::read_csv(demography_filepath) 
# Note: The demography.csv has to exist b/c Python generated it 
# and b/c model has to create it. Therefore, this error handling is in the 
# python code and this R script will not run if it does not exist.

  # Make sure the names are consistent.
  colnames(demography)=c("SubAdminID","N")


# ---------------------------------------------
# Begin Matrix Construction. ------------------
# ---------------------------------------------

# Create standard data frame. ---------
SubAdmin_Standard=data.frame(SubAdminID=subadmin$SubAdminID,SubAdminName=subadmin$FullName) 

# Create the initial sample data frame. ----------- 
Data_df0=as.data.frame(cbind(sample$SubAdminID,sample$Species,sample$Result))
  
  # If no sample data, quit the session.
  if (as.numeric(nrow(Data_df0))==0){
    line="<p>We're sorry. The sample data does not contain at least one test result. Please go back to the Warehouse and select a different set of samples to analyze.</p>"
    write(line,file=model_log_filepath,append=TRUE) 
    # Quit the session. 
    quit(status=70)}
  
  # If sample data exists, name the columns. 
  colnames(Data_df0)=c("SubAdminID","Species","Result")

    # Write a note to user about non-definitive results. 
    line="<p>Note: The CWD Data Warehouse can store records with 'Detected', 'Not Detected', 'Inconclusive', 'Pending', and 'Not tested' results.</p>" 
    write(line,file=model_log_filepath,append=TRUE)
    line="<p>However, the Simple Undetected Prevalence Estimator only summarizes 'Not Detected' results in disease-free sub-administrative areas.</p>" 
    write(line,file=model_log_filepath,append=TRUE)

# Retain samples with Result = Detected. -------------
TidyData_Result_Detected=subset(Data_df0,Result=="Detected")
PosDim=as.numeric(nrow(TidyData_Result_Detected))

# Retain samples with Result = Not Detected. ----------------
TidyData_Result_NotDetected=subset(Data_df0,Result=="Not Detected")
NegDim=as.numeric(nrow(TidyData_Result_NotDetected))

        # If both Detected and Non Detected exist.
        if (PosDim>0 & NegDim>0){
        TidyDataDefinitiveTest=as.data.frame(rbind(TidyData_Result_Detected,TidyData_Result_NotDetected))
        # Don't tell the user anything at this point, because we still don't know if 
        # records exist in healthy sub-administrative areas. We will determine this below. 
        } # End if both Detected and Non Detected exist.

        # If only Detected exists, quit the program. 
        if (PosDim>0 & NegDim==0){
        # Tell the user you cannot use this tool. 
        line="<p>We're sorry. The Simple Undetected Prevalence Estimator requires CWD-non detect results.</p>"
        write(line,file=model_log_filepath,append=TRUE) 
        line="<p>Only CWD-positive tests appear in the selected data.</p>"
        write(line,file=model_log_filepath,append=TRUE) 
        line="<p>Return to the CWD Data Warehouse and select a different set of sample data.</p>"
        write(line,file=model_log_filepath,append=TRUE) 
        # Quit the session.
        quit(status=70)
        } # End if only Detected exists.

        # If only Not-Detected exists, let the user know how many.  
        if (PosDim==0 & NegDim>0){
        TidyDataDefinitiveTest=as.data.frame(TidyData_Result_NotDetected)
        # Tell the user the number of negative tests. 
        line=paste("<p>Successfully loaded ",NegDim, "records with a 'Not Detected' test result.</p>")
        write(line,file=model_log_filepath,append=TRUE)
        } # End if only Not-Detected exist.	

        # If nothing exists, quit the program. 
        if (PosDim==0 & NegDim==0) {
        # Tell the user you cannot use this tool. 
        line="<p>We're sorry. The Simple Undetected Prevalence Estimator requires a series of CWD-non detect results.</p>"
        write(line,file=model_log_filepath,append=TRUE) 
        line="<p>Once this program completed data cleaning, no eligible samples remained.</p>"
        write(line,file=model_log_filepath,append=TRUE) 
        line="<p>Return to the CWD Data Warehouse and select a different set of sample data.</p>"
        write(line,file=model_log_filepath,append=TRUE) 
        # Quit the session.
        quit(status=70) 
        } # End if nothing exists. 

# Note: -------------------
# At this point, the data frame named TidyDataDefinitiveTest must exist and 
# contain data, or else the program was terminated.  

# Now retain samples with known sub-administrative area. 
TidyData=subset(TidyDataDefinitiveTest,complete.cases(TidyDataDefinitiveTest$SubAdminID))

# Get the counts of positive and negative by SubAdminID. 
TABLE1=as.data.frame(TidyData%>%group_by(SubAdminID,Result)%>%count(Result))

# If a Subadmin area shows up twice in the table, that means it has both positives and negatives, and is therefore ineligible. 
# Filter the table to only include Subadmin areas that show up once. [i.e., Completely remove Subadmin areas that show up twice.]
TABLE2=as.data.frame(TABLE1%>%group_by(SubAdminID)%>%filter(n()<2))
TABLE2_Dim=as.numeric(nrow(TABLE2))

# Initialize the number of non-detect sub-administrative areas.
# Zero will be replaced by data if data exist. 
NonDetect_Dim=0

# If records exist, replace that initialized number with data. 
if (TABLE2_Dim>0){
# Get the number of non-detects counties. 
NonDetect=subset(TABLE2,Result=="Not Detected")
NonDetect_Dim=as.numeric(nrow(NonDetect))}

    # If at least one non-detect record with known sub-admin area still exists. 
    if (NonDetect_Dim>0){
    # Report the number of samples within a healthy sub-admin area. 
    line=paste("<p>Successfully summarized non-detects in ",NonDetect_Dim, " healthy sub-administrative areas.</p>")
    write(line,file=model_log_filepath,append=TRUE)
    } # End if at least one eligible record still exists. 

    # If eligible records no longer exist. 
    if (NonDetect_Dim==0){
    # Write a note.
    line="<p>After cleaning the sample data, no healthy sub-administrative areas remained.</p>" 
    write(line,file=model_log_filepath,append=TRUE)
    line="<p>Return to the CWD Data Warehouse and select a different set of sample data.</p>" 
    write(line,file=model_log_filepath,append=TRUE)
    # Quit the session.
    quit(status=70)
    } # End if eligible records no longer exist. 

# Note. At this point in the code, NonDetect must have at least one record, 
# or else the code has been terminated. 

# Append the total population size from the demography file. 

# Append the output data to the standardized SubAdmin frame. 
DataForMath=merge(NonDetect,demography,by = c("SubAdminID"),all.x=TRUE)

# Obtain the vectors of data used in the math. 
N=as.numeric(DataForMath$N) # Population size.
n=as.numeric(DataForMath$n) # All non-detect sample size.
CONFIDENCE=as.numeric(rep(confidence,length(n)))
SENSITIVITY=as.numeric(rep(Sens,length(n)))

# Create the functions.
# Bayesian.
upperBayes=function(N,n,CONFIDENCE){ 
  i=0
  p0=pbetabinom(i,N-n,1/(n+2),1/(n+3))
  while (p0<CONFIDENCE){
    i=i+1
    p0=p0+dbetabinom(i,N-n,1/(n+2),1/(n+3))}
  i/N}

# Frequentist.
upperFreq=function(N,n,CONFIDENCE){ 
  j=0
  p1=1
  while(p1>1-CONFIDENCE){
    j=j+1
    p1=1*((N-n-j)/(N-j))}
  j/N}

# Frequentist with sensitivity.
upperFreqSe=function(N,n,CONFIDENCE,SENSITIVITY){ 
  d=0
  p2=1
  while(p2>1-CONFIDENCE){
    d=d+1
    y=0:min(n,d)
    p2=sum(dhyper(y,d,N-d,n)*(1-SENSITIVITY)^y)}
  d/N}

# Initialize empty vectors to hold outputs.
bayes=c()
freq=c()
freq.se=c()

# Calculate Bayesian upper bounds for all N and n combinations.
for(k in 1:length(n)){
  bayes[k]=upperBayes(N[k],n[k],CONFIDENCE[k])
  freq[k]=upperFreq(N[k],n[k],CONFIDENCE[k])
  freq.se[k]=upperFreqSe(N[k],n[k],CONFIDENCE[k],SENSITIVITY[k])
} # End for k. 

# Collapse into a single output matrix. 
MATRIX=cbind(DataForMath,bayes,freq,freq.se)

# Merge output matrix into the standard data frame. 
StandardMatrix=merge(SubAdmin_Standard, MATRIX,by=c("SubAdminID"),all.x=TRUE)

# Write the Output Matrix to the attachments working directory.
setwd("/data/attachments")
write.csv(StandardMatrix, "SimpleUndetectedPrevalenceEstimatorOutput.csv",  row.names=FALSE)

# Modify the attachments.json file to include the Model Matrix.
setwd("/data")

# Define the new item.
attachment_item=list(
  filename="SimpleUndetectedPrevalenceEstimatorOutput.csv", 
  content_type="text/csv", 
  role="downloadable")
add_item_to_json_array("attachments.json", attachment_item)