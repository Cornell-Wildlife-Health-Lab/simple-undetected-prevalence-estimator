'''
Script Name: Simple Undetected Prevalence Estimator Input Processing
Author: Nicholas Hollingshead, Cornell University
Description: Prepares data from the CWD Data Warehouse for the Simple Undetected Prevalence Estimator R script.
Inputs: 
  params.json
  sub_administrative_area.ndJson
  sample.ndJson
  demography.json
Outputs: 
  params.csv
  sub_administrative_area.csv
  sample.csv
  demography.csv
  info.txt
  execution_log.log
'''

##############
# Environment
import sys
import os
import ndjson
import json
import pathlib
import csv
import logging
import datetime

##################
# SCRIPT VARIABLES

if os.name == 'nt':  # Windows
  base_path = pathlib.Path("data")
else: # Assuming Linux/Docker
  base_path = pathlib.Path("/data")

parameters_file_path = base_path / "params.json"
subadmin_file_path = base_path / "sub_administrative_area.ndJson"
sample_file_path = base_path / "sample.ndJson"
demography_file_path = base_path / "demography.ndJson"

model_metadata_log_file = base_path / "attachments" / "info.html"
logging_path = base_path / "attachments" / "execution_log.log"
attachments_json_path = base_path / "attachments.json"

###########
# FUNCTIONS

def model_log_html(line='', html_element="p", filename=model_metadata_log_file):
    """
    Writes a single line to the model_metadata_log text file with specified HTML element.

    Args:
        line: The line to be written.
        filename: The name of the file.
        html_element: The HTML element tag to use (e.g., "h1", "h2", "p", "div").
    """
    with open(filename, 'a') as f:
        f.write(f"<{html_element}>{line}</{html_element}>" + '\n')


def add_item_to_json_file_list(file_path, new_item):
  """
  Adds a new item to the list within a JSON file.

  Args:
    file_path: Path to the JSON file.
    new_item: The item to be added to the list.

  Raises:
    FileNotFoundError: If the specified file does not exist.
    json.JSONDecodeError: If the file content is not valid JSON.
  """

  try:
    with open(file_path, 'r') as f:
      data = json.load(f)

    if isinstance(data, list):
      data.append(new_item)
    else:
      raise ValueError("The JSON file does not contain a list.")

    with open(file_path, 'w') as f:
      json.dump(data, f, indent=2) 

  except FileNotFoundError:
    print(f"Error: File '{file_path}' not found.")
    raise
  except json.JSONDecodeError:
    print(f"Error: Invalid JSON in '{file_path}'.")
    raise
  except ValueError as e:
    print(f"Error: {e}")
    raise

def json_stringify(data, indent=3):
  """Custom formats a nested dictionary into a string with spaces for indentation.

  Args:
    data: The nested dictionary.
    indent: The number of spaces for indentation.

  Returns:
    A formatted string.
  """

  def format_helper(data, level):
    lines = []
    for key, value in data.items():
      if isinstance(value, dict):
        lines.append(f"{(' ' * level)}{key}:")
        lines.extend(format_helper(value, level + indent))
      else:
        lines.append(f"{(' ' * level)}{key}: {value}")
    return lines

  return '\n'.join(format_helper(data, indent))


def rename_key(dict_, old_key, new_key):
  """Renames a key in a dictionary.

  Args:
    dict_: The dictionary to modify.
    old_key: The key to be renamed.
    new_key: The new key name.
  """

  if old_key in dict_:
    dict_[new_key] = dict_.pop(old_key)

######################
# SETUP FILE STRUCTURE

# Create the attachments directory structure recursively if it doesn't already exist.
os.makedirs(os.path.dirname(model_metadata_log_file), exist_ok=True)

# Create attachments.json file which will contain a list of all attachments generated
# Initially, the attachments is simply an empty list
with open(attachments_json_path, 'w', newline='') as f:
  writer = json.dump(list(), f)

# Append execution log to attachments.json for developer feedback
attachment = {
  "filename": "execution_log.log", 
  "content_type": "text/plain", 
  "role": "downloadable"
  }
add_item_to_json_file_list(attachments_json_path, attachment)

# append info log to the attachments.json for user feedback
attachment = {
  "filename": "info.html", 
  "content_type": "text/html", 
  "role": "feedback"}
add_item_to_json_file_list(attachments_json_path, attachment)

###############
# SETUP LOGGING

# Create log file including any parent folders (if they don't already exist)
os.makedirs(os.path.dirname(logging_path), exist_ok=True)

logging.basicConfig(level = logging.DEBUG,
                    filename = logging_path, 
                    filemode = 'w',
                    datefmt = '%Y-%m-%d %H:%M:%S',
                    format = '%(asctime)s - %(levelname)s - %(message)s')

# Uncaught exception handler
def handle_uncaught_exception(exc_type, exc_value, exc_traceback):
  """
  Handles uncaught exceptions by logging the traceback and other details.

  Args:
    exc_type: The type of the exception.
    exc_value: The exception instance.
    exc_traceback: The traceback object.
  """
  logging.error("Uncaught exception:", exc_info=(exc_type, exc_value, exc_traceback))
sys.excepthook = handle_uncaught_exception 

# Initiate model metadata log
# Clear model log file contents if necessary.
open(model_metadata_log_file, 'w').close()
model_log_html("Model Execution Summary", "h3")
model_log_html("Model: Simple Undetected Prevalence Estimator Model")
model_log_html('Date: ' + datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S") + ' GMT')
logging.info("Model: Simple Undetected Prevalence Estimator Model")
logging.info('Date: ' + datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S") + ' GMT')
logging.info("This log records data for debugging purposes in the case of a model execution error.")

####################
# Process Parameters
# Required

# Get parameters file
try:
  with open(parameters_file_path, 'r') as f:
    params = json.load(f)
    logging.info("Parameter file loaded successfully")
except FileNotFoundError:
  # The model cannot be executed without a params file. Exit with an error immediately.
  logging.error("params.json File does not exist.")
  model_log_html("ERROR", "h4")
  model_log_html("Parameters (params.json) file not found.")
  sys.exit(1)

# Get provider admin area for logging
provider_admin_area = params['_provider']['_administrative_area']['administrative_area']
model_log_html(f'Provider area: {provider_admin_area}')
# Remove Provider parameter, which is not used in this model and is nested
del(params['_provider'])
# Add parameter related content to the log
model_log_html('User provided parameters', "h4")
model_log_html(json_stringify(params))

########################
# Process Subadmin Areas
# Required

try:
  with open(subadmin_file_path, 'r') as f:
    subadmin_areas = ndjson.load(f)
    logging.info("sub_administrative_area.ndJson file loaded successfully")
except FileNotFoundError:
  # The subadmin areas file cannot be found. Exit with an error immediately.
  logging.error("sub_administrative_area.ndJson File does not exist.")
  model_log_html("ERROR", "h4")
  model_log_html("Subadmin areas (sub_administrative_area.ndJson) file was expected but not found.")
  sys.exit(1)

# Get just the properties needed:
# _id, and full_name (all required)
subadmin_areas_data = []
for sa in subadmin_areas:
  subadmin_area_dict = {}
  # All of the following properties are required, so do not need to check if they exist  
  subadmin_area_dict['_id'] = sa['_id']
  subadmin_area_dict['name'] = sa['name']
  subadmin_area_dict['full_name'] = sa['full_name']
  subadmin_area_dict['aland'] = sa['aland']
  subadmin_areas_data.append(subadmin_area_dict)

# Write subadmin areas to a CSV
with open(pathlib.Path(base_path / "sub_administrative_area.csv"), 'w', newline='') as f:
  writer = csv.DictWriter(
    f, 
    quoting = csv.QUOTE_NONNUMERIC,
    fieldnames = ["_id", "full_name", "name", "aland"],
    extrasaction='ignore'
    )
  writer.writeheader()
  writer.writerows(subadmin_areas_data)

####################
# Process Demography
# required

try:
  with open(demography_file_path, 'r') as f:
    demography = ndjson.load(f)
    logging.info("Demography file loaded successfully")
except FileNotFoundError:
  # The demography file cannot be found. Exit with an error immediately.
  logging.error("demography.json file does not exist.")
  model_log_html("ERROR", "h4")
  model_log_html("Demography (demography.json) file was expected but not found.")
  sys.exit(1)


for demo in demography:
  # If deer density given, convert to total population using the land area for the sub-administrative area
  if demo.get('metric') == 'deer density':
    for sa_id, original_density_value in demo['data'].items():
      # Find the corresponding sub-administrative area data
      for sa in subadmin_areas_data:
        if sa.get('_id') == sa_id:          
          # Deer density is in deer per square kilometer and aland is in square meters.
          # aland is in square meters. Convert aland to square kilometers by dividing by 1,000,000.
          aland_sq_km = sa['aland'] / 1_000_000 # Use 1_000_000 for readability
          new_total_population = int(round(original_density_value * aland_sq_km))
          demo['data'][sa_id] = new_total_population
          break # Exit the inner loop once a match is found for sa_id  
    # After processing all data points for this 'deer density' entry, update the metric name
    demo['metric'] = 'total population (converted from density)'

# Sum total population by sub-administrative area
demography_data_dict = dict()
for demo in demography:
  for key, value in demo['data'].items():
    if key in demography_data_dict:
      demography_data_dict[key] += value
    else:
      demography_data_dict[key] = value

# Convert into a list of dictionaries
demography_data = list()
for key, value in demography_data_dict.items():
  demography_data.append(
    {
      '_id': key,
      'value': value
    }
  )

# Log demography metrics used
model_log_html(f"Demographic data", "h4")
for demo in demography:
  model_log_html(f"{demo['species']} {demo['metric']} for season-year {demo['season_year']}")

# Write the demography data to a CSV
with open(pathlib.Path(base_path / "demography.csv"), 'w', newline='') as f:
  writer = csv.DictWriter(
    f, 
    quoting=csv.QUOTE_NONNUMERIC,
    fieldnames=["_id", "value"], 
    extrasaction='ignore')
  writer.writeheader()
  writer.writerows(demography_data)

#################
# Process Samples
# Required

try:
  with open(sample_file_path, 'r') as f:
    sample_data = ndjson.load(f)
    logging.info("Sample file loaded successfully")
except FileNotFoundError:
  # The subadmin areas file cannot be found. Exit with an error immediately.
  logging.error("sample.ndJjon File does not exist.")
  model_log_html("ERROR", "h4")
  model_log_html("Sample (sample.ndJson) file was expected but not found.")
  sys.exit(1)

for sample_record in sample_data:
  # For each sample, get the definitive test result
  # Create a list of tests that are flagged as selected_definitive (should have length 0 or 1)
  tests_selected_definitive = [test for test in sample_record["tests"] if test["selected_definitive"] == True]
  
  if len(tests_selected_definitive) == 0: # no match means no tests so set to None
    sample_record["result"] = None
  elif len(tests_selected_definitive) > 1: # more than one match - problem
    pass # This would be a problem and should never happen due to database limits
  elif len(tests_selected_definitive) == 1: # one match so use that test
    # result is a required field; but check if has value. If so, use it, else set to None
    sample_record["result"] = tests_selected_definitive[0]["result"] if "result" in tests_selected_definitive[0] else None
  
  # Get sub-administrative area for each sample
  # If the sample has no sub-administrative area or if the sub-administrative
  # area has no id, then return None.
  if '_sub_administrative_area' in sample_record:
    if '_id' in sample_record['_sub_administrative_area']:
      sample_record["sub_administrative_area_id"] = sample_record['_sub_administrative_area']['_id']
    else:sample_record["sub_administrative_area_id"] = None
  else:sample_record["sub_administrative_area_id"] = None
  
  # Rename _id field
  if '_id' in sample_record:
    rename_key(sample_record, '_id', 'id')

# Write to a CSV
with open(pathlib.Path(base_path / "sample.csv"), 'w', newline='') as f:
  writer = csv.DictWriter(
    f, 
    quoting=csv.QUOTE_NONNUMERIC,
    fieldnames=["id", "species", "sample_source","season_year", "age_group","sex", "result", "sub_administrative_area_id"], 
    extrasaction='ignore')
  writer.writeheader()
  writer.writerows(sample_data)
 
##############
# Params processing - continued

# Write revised parameters to a CSV file
with open(pathlib.Path(base_path / "params.csv"), 'w', newline='') as f:
  field_names = ["alpha", "sensitivity"]
  writer = csv.DictWriter(
    f, 
    quoting=csv.QUOTE_NONNUMERIC,
    fieldnames=field_names, 
    extrasaction='ignore')
  writer.writeheader()
  writer.writerow(params)