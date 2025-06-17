#!/bin/bash
python3 "/app/scripts/input_processing.py"
exit_status=$?  # Capture exit code
echo "Exit status: $exit_status"

# Check if the first exit code is zero (successful)
if [ $exit_status -eq 0 ]; then
  echo "Input processing ran successfully. Run model script."
  Rscript "/app/scripts/SimpleUndetectedPrevalenceEstimator.R"
  exit_status=$?
  echo "Exit status: $exit_status"
else
  echo "Input processing failed. Exit status: $exit_status"
  exit $exit_status
fi

# Check the exit code of the R script
if [ $exit_status -eq 0 ]; then
  echo "Model script ran successfully. Run output processing script."
  python3 "/app/scripts/output_processing.py"
  exit_status=$?
  echo "Exit status: $exit_status"
else
  echo "Model script failed. Exit status: $exit_status"
  exit $exit_status
fi

# Exit with the final exit status
if [ $exit_status -eq 0 ]; then
  echo "Output processing script ran successfully. Exit status: $exit_status"
else
  echo "Output processing script failed. Exit status: $exit_status"
fi

exit $exit_status