# see https://itnext.io/docker-makefile-x-ops-sharing-infra-as-code-parts-ea6fa0d22946

# suppress makes own output
.SILENT:

# import config.
# You can change the default config with `make cnf="config_special.env" build`
cnf ?= config.env
include $(cnf)
export $(shell sed 's/=.*//' $(cnf))

# import deploy config
# You can change the default deploy config with `make cnf="deploy_special.env" release`
dpl ?= deploy.env
include $(dpl)
export $(shell sed 's/=.*//' $(dpl))

# If you see pwd_unknown showing up, this is why. Re-calibrate your system.
PWD ?= pwd_unknown

# if vars not set specifially: try default to environment, else fixed value.
# strip to ensure spaces are removed in future editorial mistakes.
# tested to work consistently on popular Linux flavors and Mac.
ifeq ($(user),)
# USER retrieved from env, UID from shell.
HOST_USER ?= $(strip $(if $(USER),$(USER),nodummy))
HOST_UID ?= $(strip $(if $(shell id -u),$(shell id -u),4000))
else
# allow override by adding user= and/ or uid=  (lowercase!).
# uid= defaults to 0 if user= set (i.e. root).
HOST_USER = $(user)
HOST_UID = $(strip $(if $(uid),$(uid),0))
endif

GIT_HASH ?= $(shell git log --format="%h" -n 1)
THIS_FILE := $(lastword $(MAKEFILE_LIST))
CMD_ARGUMENTS ?= $(cmd)

# export such that its passed to shell functions for Docker to pick up.
export PROJECT_NAME
export HOST_USER
export HOST_UID

# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
.DEFAULT_GOAL := help

# shell is the first target. So instead of: make shell cmd="whoami", we can type: make cmd="whoami".
# more examples: make shell cmd="whoami && env", make shell cmd="echo hello container space".
# leave the double quotes to prevent commands overflowing in makefile (things like && would break)
# special chars: '',"",|,&&,||,*,^,[], should all work. Except "$" and "`", if someone knows how, please let me know!).
# escaping (\) does work on most chars, except double quotes (if someone knows how, please let me know)
# i.e. works on most cases. For everything else perhaps more useful to upload a script and execute that.
shell:
ifeq ($(CMD_ARGUMENTS),)
	# no command is given, default to shell
	docker-compose -p $(PROJECT_NAME)_$(HOST_UID) run --rm $(SERVICE_TARGET) sh
else
	# run the command
	docker-compose -p $(PROJECT_NAME)_$(HOST_UID) run --rm $(SERVICE_TARGET) sh -c "$(CMD_ARGUMENTS)"
endif
######### DOCKER TASKS ###########
.PHONY: build
build: # Build the container
	@docker build --tag ${DOCKER_USERNAME}/${PROJECT_NAME}:${GIT_HASH} .

.PHONY: rebuild
rebuild: # force a rebuild by passing --no-cache
	@docker build --no-cache -t ${DOCKER_USERNAME}/${PROJECT_NAME}:${GIT_HASH} .

.PHONY: pull
pull:
	@docker pull ${DOCKER_USERNAME}/${PROJECT_NAME}:${GIT_HASH}

.PHONY: push
push:
	@docker push ${DOCKER_USERNAME}/${PROJECT_NAME}:${GIT_HASH}

.PHONY: tag-latest
	@docker tag  ${DOCKER_USERNAME}/${PROJECT_NAME}:${GIT_HASH} ${DOCKER_USERNAME}/${PROJECT_NAME}:latest

.PHONY: release
release: pull tag-latest push
	@docker push ${DOCKER_USERNAME}/${PROJECT_NAME}:latest

# TODO make clean
clean:
	# remove created images
	@docker rm $(docker ps --filter status=exited -q)
	# @docker-compose -p $(PROJECT_NAME)_$(HOST_UID) down --remove-orphans --rmi all 2>/dev/null \
	# && echo 'Image(s) for "$(PROJECT_NAME):$(HOST_USER)" removed.' \
	# || echo 'Image(s) for "$(PROJECT_NAME):$(HOST_USER)" already removed.'

.PHONY: prune
prune:	# clean all that is not actively used
	@docker system prune -af

.PHONY: run
run: ## Run container on port configured in `config.env`
	docker run -d \
		-p $(PORT):$(PORT) \
		--env-file=./config.env \
	    --env AUTHENTICATE_VIA_JUPYTER="${JUPYTER_TOKEN}" \
		--name $(PROJECT_NAME) \
		-v "${VOLUME}:/workspace" \
		--shm-size 1024m \
    	--restart always \
		${DOCKER_USERNAME}/${PROJECT_NAME}:latest

.PHONY: up
up: build run ## Run container on port configured in `config.env` (Alias to run)

.PHONY: stop
stop: ## Stop and remove a running container
	@docker stop $(PROJECT_NAME); docker rm -f $(PROJECT_NAME)

.PHONY: version
version: ## Output the current version
	@echo $(GIT_HASH)
