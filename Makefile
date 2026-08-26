SERVICE_NAME=datahub-models-ccdm-mapping
export TMS_PROJECT_NAME ?= $(SERVICE_NAME)
TF_config_path := datahub-tms-pipeline/terraform

include datahub-tms-pipeline/tms.mk

set-pipeline-metadata:
	@true
.PHONY: set-pipeline-metadata
