 # Populate the environment (https://stackoverflow.com/questions/44628206/how-to-load-and-export-variables-from-an-env-file-in-makefile/44637188#44637188)
include .env
VARS:=$(shell sed -ne 's/ *\#.*$$//; /./ s/=.*$$// p' .env )
$(foreach v,$(VARS),$(eval $(shell echo export $(v)="$($(v))")))

ifndef APP_NAME
	APP_NAME = blog
endif

ifndef WORDPRESS_VERSION
	WORDPRESS_VERSION = 5.5.1
endif

ifndef PHP_VERSION
	PHP_VERSION = 7.4
endif

ifndef DB_NAME
	DB_NAME = $(APP_NAME)-database
endif

ifndef DB_TYPE
	DB_TYPE = mysql
endif

ifndef DB_VERSION
	DB_VERSION = 5.6
endif

ifndef PHP_BUILDPACK_VERSION
	PHP_BUILDPACK_VERSION = v180
endif

ifndef DOKKU_USER
	DOKKU_USER = dokku
endif

ifndef WP_DEBUG
	WP_DEBUG = false
endif

ifdef UNATTENDED
	DOKKU_CMD = ssh $(DOKKU_USER)@$(SERVER_NAME)
else
	DOKKU_CMD = dokku
endif

CURL_INSTALLED := $(shell command -v curl 2> /dev/null)
WGET_INSTALLED := $(shell command -v wget 2> /dev/null)
ARGS = $(filter-out $@,$(MAKECMDGOALS))

# get current wordpress version if it exists
ifneq ("$(wildcard app/$(APP_NAME))", "")
	APP_EXISTS = true
	CURRENT_WORDPRESS_VERSION = $(shell sed -n "s/.*\$$wp_version = \'\(.*\)\';.*/\1/p" app/$(APP_NAME)/wp-includes/version.php)
endif

default: build

.PHONY: help
help: ## this help.
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-36s\033[0m %s\n", $$1, $$2}'


##
# App (Dokku)
#

.PHONY: composer_update ## update composer packages in the app
composer_update:
	@echo "# ensuring the composer.json loads php $(PHP_VERSION) with the ext-gd extension providing PNG, JPEG and FreeType support";
	@echo "# ...hang tight, this could take a minute or more...";
	@(sed 's/PHP_VERSION/$(PHP_VERSION)/' config/composer.json > app/$(APP_NAME)/composer.json && cd app/$(APP_NAME) && php /usr/local/bin/composer.phar install --ignore-platform-reqs && rm -rf vendor && git add composer.json composer.lock && git diff-index --quiet --cached HEAD || git commit -qm "Use PHP $(PHP_VERSION) with ext-gd extension")

.PHONY: build
build: ## builds (or updates) a wordpress blog installation and outputs deploy instructions
ifndef APP_NAME
	$(error "Missing APP_NAME environment variable, this should be the name of your blog app")
endif
ifndef SERVER_NAME
	$(error "Missing SERVER_NAME environment variable, this should be something like 'dokku.me'")
endif
ifndef CURL_INSTALLED
ifndef WGET_INSTALLED
	$(error "Neither curl nor wget are installed, and at least one is necessary for retrieving salts")
endif
endif

ifdef APP_EXISTS # If app directory already exists
	@echo "# directory \"app/$(APP_NAME)\" already exists, commence updating"
ifneq ($(CURRENT_WORDPRESS_VERSION), $(WORDPRESS_VERSION))
	@echo "# wordpress $(CURRENT_WORDPRESS_VERSION) will be updated to $(WORDPRESS_VERSION)"
	@(cd app/$(APP_NAME) && git remote set-branches --add origin $(WORDPRESS_VERSION) && git fetch origin $(WORDPRESS_VERSION):latest && git merge -X theirs latest && git add -a && git diff-index --quiet --cached HEAD || git commit -qm "Updated WordPress to $(WORDPRESS_VERSION)")
else
	@echo "# wordpress $(CURRENT_WORDPRESS_VERSION) is already installed, skipping"
endif
else # If app directory does not exist
	# creating the wordpress repo
	@(git -c advice.detachedHead=false clone --branch=$(WORDPRESS_VERSION) --single-branch https://github.com/WordPress/WordPress.git app/$(APP_NAME) && cd app/$(APP_NAME) && git checkout -qb master);
endif
	@echo ""
	# Adding dependencies...
	# adding wp-config.php from config
	@(cp config/wp-config.php app/$(APP_NAME)/wp-config.php && cd app/$(APP_NAME) && git add wp-config.php && git diff-index --quiet --cached HEAD || git commit -qm "Adding environment-variable based wp-config.php")
	# adding .buildpacks file to configure heroku buildpacks
	@(sed 's/PHP_BUILDPACK_VERSION/$(PHP_BUILDPACK_VERSION)/' config/.buildpacks > app/$(APP_NAME)/.buildpacks && cd app/$(APP_NAME) && git add .buildpacks && git diff-index --quiet --cached HEAD || git commit -qm "Specify heroku buildpacks")
	# adding apt-packages file to configure system packages
	@(cp config/apt-packages app/$(APP_NAME)/apt-packages && cd app/$(APP_NAME) && git add apt-packages && git diff-index --quiet --cached HEAD || git commit -qm "Specify system dependencies Aptfile")
ifdef APP_EXISTS # If app directory already exists
	@echo update composer? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]]; then make composer_update; else echo "# skipping composer update"; fi
else
	@make composer_update
endif
	# 🐛 adding test.php to server 🐛
	# @(echo '<?php die( $$_SERVER['SERVER_NAME'] ); ?>' > app/$(APP_NAME)/test.php  && cd app/$(APP_NAME) && git add test.php && git diff-index --quiet --cached HEAD || git commit -qm "Adding test.php to server")
	# adding Procfile to configure webserver
	@(cp config/Procfile app/$(APP_NAME)/Procfile && cd app/$(APP_NAME) && git add Procfile && git diff-index --quiet --cached HEAD || git commit -qm "Adding Procfile to specify webserver")
	# adding .user.ini file to configure PHP
	@(cp config/.user.ini app/$(APP_NAME)/.user.ini && cd app/$(APP_NAME) && git add .user.ini && git diff-index --quiet --cached HEAD || git commit -qm "Adding .user.ini to specify PHP settings")
	# adding .profile script to modify heroku environment
	@(cp config/.profile app/$(APP_NAME)/.profile && cd app/$(APP_NAME) && git add .profile && git diff-index --quiet --cached HEAD || git commit -qm "Adding .profile to specify environment settings")
	# adding nginx conf file to configure host NGINX
	@(cp config/nginx.conf.sigil app/$(APP_NAME)/nginx.conf.sigil && cd app/$(APP_NAME) && git add nginx.conf.sigil && git diff-index --quiet --cached HEAD || git commit -qm "Adding nginx.conf.sigil to specify host NGINX settings")
	# adding nginx conf file to configure container NGINX
	@(cp config/nginx.inc.conf app/$(APP_NAME)/nginx.inc.conf && cp config/h5bp_mime.types app/$(APP_NAME)/h5bp_mime.types && cd app/$(APP_NAME) && git add nginx.inc.conf h5bp_mime.types && git diff-index --quiet --cached HEAD || git commit -qm "Adding nginx.inc.conf & h5bp_mime.types to specify container NGINX settings")
	# adding favicon.ico to site
	@(cp config/favicon.ico app/$(APP_NAME)/favicon.ico && cd app/$(APP_NAME) && git add favicon.ico && git diff-index --quiet --cached HEAD || git commit -qm "Adding favicon.ico")
	# setting the correct dokku remote for app and server combination
	@cd app/$(APP_NAME) && (git remote rm dokku 2> /dev/null || true) && git remote add dokku "dokku@$(SERVER_NAME):$(APP_NAME)"
	# retrieving potential salts and writing them to /tmp/wp-salts
ifdef CURL_INSTALLED
	@curl -so /tmp/wp-salts https://api.wordpress.org/secret-key/1.1/salt/
else
ifdef WGET_INSTALLED
	@wget -qO /tmp/wp-salts https://api.wordpress.org/secret-key/1.1/salt/
endif
endif
	@sed -i.bak -e 's/ //g' -e "s/);//g" -e "s/define('/$(DOKKU_CMD) config:set $(APP_NAME) /g" -e "s/SALT',/SALT=/g" -e "s/KEY',[ ]*/KEY=/g" /tmp/wp-salts && rm /tmp/wp-salts.bak

ifndef UNATTENDED
ifndef APP_EXISTS # If app directory already exists we assume the app is already built
	@make instructions
else
	@echo show instructions? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]]; \
	then \
		make instructions; \
	else \
		echo '# skipping setup instructions, if you need to see them run `make instructions`'; \
	fi
	@echo deploy app now? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]]; \
	then \
		make deploy; \
	else \
		echo ""; \
		echo "# now, on your local machine, change directory to your new wordpress app, and push it up"; \
		echo ""; \
		echo "cd app/$(APP_NAME)"; \
		echo "git push dokku master"; \
	fi
endif
else
	@chmod +x /tmp/wp-salts
	$(DOKKU_CMD) apps:create $(APP_NAME)
	$(DOKKU_CMD) storage:mount $(APP_NAME) /var/lib/dokku/data/storage/$(APP_NAME)/wp-content:/app/wp-content
	$(DOKKU_CMD) ln -s /var/lib/dokku/data/storage/$(APP_NAME)/wp-content ~/wp-content
	$(DOKKU_CMD) $(DB_TYPE):create $(DB_NAME)
	$(DOKKU_CMD) $(DB_TYPE):link $(DB_NAME) $(APP_NAME)
	@/tmp/wp-salts
	@echo ""
	# run the following commands on the server to ensure data is stored properly on disk
	@echo ""
	@echo "sudo mkdir -p /var/lib/dokku/data/storage/$(APP_NAME)/wp-content"
	@echo "sudo chown 32767:32767 /var/lib/dokku/data/storage/$(APP_NAME)/wp-content"
	@echo ""
	@echo deploy app now? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]]; \
	then \
		make deploy; \
	else \
		echo ""; \
		echo "# now, on your local machine, change directory to your new wordpress app, and push it up"; \
		echo ""; \
		echo "cd app/$(APP_NAME)"; \
		echo "git push dokku master"; \
	fi
endif

.PHONY: instructions
instructions: ## shows app setup instructions
	@echo ""
	# run the following commands on the server to setup the app:
	@echo ""
	@echo "dokku apps:create $(APP_NAME)"
	@echo ""
	# setup persistent storage
	@echo ""
	@echo "sudo mkdir -p /var/lib/dokku/data/storage/$(APP_NAME)/wp-content"
	@echo "sudo chown 32767:32767 /var/lib/dokku/data/storage/$(APP_NAME)/wp-content"
	@echo "dokku storage:mount $(APP_NAME) /var/lib/dokku/data/storage/$(APP_NAME)/wp-content:/app/wp-content"
	@echo "ln -s /var/lib/dokku/data/storage/$(APP_NAME)/wp-content ~/wp-content"
	@echo ""
	# install dokku-apt to add linux files to the container
	@echo ""
	@echo "sudo dokku plugin:install https://github.com/dokku-community/dokku-apt apt"
	@echo ""
	# install the dokku database plugin if it's not already:
	@echo ""
	@echo "sudo dokku plugin:install https://github.com/dokku/dokku-$(DB_TYPE).git"
	@echo ""
	# setup your SQL database and link it to your app
	@echo ""
	@printf "export "
	@printf "$(DB_TYPE)" | tr [a-z] [A-Z]
	@echo "_IMAGE_VERSION=\"$(DB_VERSION)\""
	@echo "dokku $(DB_TYPE):create $(DB_NAME)"
	@echo "dokku $(DB_TYPE):link $(DB_NAME) $(APP_NAME)"
	@echo ""
	# Set the app restart policy to 'always'
	@echo ""
	@echo "dokku ps:set-restart-policy $(APP_NAME) always"
	@echo ""
	# Set the wp debug policy true (default: false)
	@echo ""
	@echo "dokku config:set $(APP_NAME) WP_DEBUG=true"
	@echo ""
	# Set the wp server name (default: getenv(SITEURL))
	@echo ""
	@echo "dokku config:set $(APP_NAME) SITEURL=$(SERVER_NAME)"
	@echo ""
	# you will also need to set the proper environment variables for keys and salts
	# the following were generated using the wordpress salt api: https://api.wordpress.org/secret-key/1.1/salt/
	# and use the following commands to set them up:
	@echo ""
	@cat /tmp/wp-salts
	@echo ""
	# now, on your local machine, change directory to your new wordpress app, and push it up
	@echo ""
	@echo "cd app/$(APP_NAME)"
	@echo "git push dokku master"

.PHONY: deploy
deploy: ## deploys the built application to the dokku server
	cd app/$(APP_NAME)/ && git push dokku master

.PHONY: destroy
destroy: ## destroys an existing wordpress blog installation and outputs undeploy instructions
ifndef APP_NAME
	$(error "Missing APP_NAME environment variable, this should be the name of your blog app")
endif
ifndef SERVER_NAME
	$(error "Missing SERVER_NAME environment variable, this should be something like 'dokku.me'")
endif
ifndef UNATTENDED
	# destroy the database
	@echo ""
	@echo "dokku $(DB_TYPE):unlink $(DB_NAME) $(APP_NAME)"
	@echo "dokku $(DB_TYPE):destroy $(DB_NAME)"
	@echo ""
	# destroy the app
	@echo ""
	@echo "dokku -- --force apps:destroy $(APP_NAME)"
	@echo ""
	# run the following commands on the server to remove storage directories on disk
	@echo ""
	@echo "rm -rf /var/lib/dokku/data/storage/$(APP_NAME)"
	@echo ""
	# now, on your local machine, cd into your app's parent directory and remove the app
	@echo ""
	@echo "rm -rf app/$(APP_NAME)"
else
	# destroy the database
	$(DOKKU_CMD) $(DB_TYPE):unlink $(DB_NAME) $(APP_NAME)
	$(DOKKU_CMD) $(DB_TYPE):destroy $(DB_NAME)
	# destroy the app
	$(DOKKU_CMD) -- --force apps:destroy $(APP_NAME)
	# run the following commands on the server to remove storage directories on disk
	@echo ""
	@echo "rm -rf /var/lib/dokku/data/storage/$(APP_NAME)"
	@echo ""
	# now, on your local machine, cd into your app's parent directory and remove the app
	@echo ""
	@echo "rm -rf app/$(APP_NAME)"
endif

.PHONY: diff_prod
diff_prod: ## compare the local app with the server app
	@cd app/$(APP_NAME) && git fetch dokku && git diff dokku/master master

.PHONY: push
push: ## send files from [<local path>] to [<hostname or USER@HOST>]:[<remote path>]
	# 🗃  first-run: omit "/" if folder DOESN'T EXIST (to create & populate it)
	# 🗂  afterwards: include "/" if folder EXISTS (to get its inner contents)
	$(eval R_HOST := $(shell sed -ne 's/:.*//p'  <<< $(word 2,$(ARGS))))
	$(eval R_PATH := $(shell sed -ne 's/^.*://p' <<< $(word 2,$(ARGS))))
	$(eval L_PATH := $(word 1,$(ARGS)))
	@echo "$(L_PATH) -> $(R_HOST):/var/lib/dokku/data/storage/$(APP_NAME)/$(R_PATH)"
	@echo path format \(\"\/\"\) correct? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]]; \
	then \
		rsync -rltzv --super --delete --filter='dir-merge,-n /.gitignore' --rsync-path="sudo rsync" --chmod=D0755,F0644 --perms --chown=32767:32767 --owner --group $(L_PATH) $(R_HOST):/var/lib/dokku/data/storage/$(APP_NAME)/$(R_PATH) ; \
		echo "✅ $(L_PATH) pushed to $(word 2,$(ARGS))" ; \
	else \
		echo "# operation canceled"; \
	fi

.PHONY: pull
pull: ## pull files from [<hostname or USER@HOST>]:[<remote path>] to [<local path>]
	# 🗃  first-run: omit "/" if folder DOESN'T EXIST (to create & populate it)
	# 🗂  afterwards: include "/" if folder EXISTS (to send its inner contents)
	$(eval R_HOST := $(shell sed -ne 's/:.*//p'  <<< $(word 1,$(ARGS))))
	$(eval R_PATH := $(shell sed -ne 's/^.*://p' <<< $(word 1,$(ARGS))))
	$(eval L_PATH := $(word 2,$(ARGS)))
	@echo "$(R_HOST):/var/lib/dokku/data/storage/$(APP_NAME)/$(R_PATH) -> $(L_PATH)"
	@echo path format \(\"\/\"\) correct? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]]; \
	then \
		rsync -rltzvp --super --delete --filter='dir-merge,-n /.gitignore' $(R_HOST):/var/lib/dokku/data/storage/$(APP_NAME)/$(R_PATH) $(L_PATH) ; \
		echo "✅ $(word 2,$(ARGS)) pulled to $(L_PATH)" ; \
	else \
		echo "# operation canceled"; \
	fi

.PHONY: sync
sync: ## sync files [<from hostname or USER@HOST>] [<to hostname or USER@HOST>]
ifneq ($(wildcard tmp/),)
	@echo empty tmp/? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]] ; \
	then \
		rm -rf tmp/ ; \
		mkdir tmp/ ; \
	fi
else
	@mkdir tmp/
endif
	$(eval ORIG := $(word 1,$(ARGS)))
	$(eval DEST := $(word 2,$(ARGS)))
	$(eval TIMESTAMP := $(shell date +"%Y%m%d%H%M%S"))
	@mkdir -p tmp/$(ORIG)/
	@echo export $(ORIG) db? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]] ; \
	then \
		ssh -t $(ORIG) bash --login -ci "'db export $(DB_NAME)_$(TIMESTAMP).sql; exit'" ; \
		mkdir -p tmp/$(ORIG)/.sql/ ; \
		scp $(ORIG):~/.sql/$(DB_NAME)_$(TIMESTAMP).sql tmp/$(ORIG)/.sql/ ; \
	fi
	@echo pull $(ORIG) wp-content? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]] ; \
	then \
		make pull $(ORIG):wp-content tmp/$(ORIG)/ ; \
	fi
	$(eval ODB := $(shell ls -t tmp/$(ORIG)/.sql/ | head -n 1 ))
	@echo import $(ORIG) db to $(DEST)? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]] ; \
	then \
		scp tmp/$(ORIG)/.sql/$(ODB) $(DEST):~/.sql/ ; \
		ssh -t $(DEST) bash --login -ci "'db import ~/.sql/$(ODB); exit'" ; \
	fi
	@echo push $(ORIG) wp-content to $(DEST)? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]] ; \
	then \
		make push tmp/$(ORIG)/wp-content/ $(DEST):wp-content/ ; \
	fi
	@echo clean up? [Y/n]
	@read line; if [[ $$line = "y" || $$line = "Y" ]] ; \
	then \
		rm -rf tmp/ ; \
	fi

.PHONY: plugit
plugit: ## download git repo to server, extract, rename, set user:group, set permissions, clean up. requires passing git `user/repo` as an argument ENV=[<configname or USER@]HOST>]
	@export DIR=$$(echo $(ARGS)$$line | cut -d'/' -f2- ) && \
		ssh -t $(ENV) bash -c "' \
		cd /var/lib/dokku/data/storage/$(APP_NAME)/wp-content/plugins/ && pwd && \
		sudo rm -f master.zip sudo rm -rf $$DIR && sudo wget https://github.com/$(ARGS)/archive/master.zip && \
		sudo unzip -q master.zip && sudo rm -f master.zip && \
		sudo mv -n $$DIR-master $$DIR && sudo chown -R 32767:32767 $$DIR && \
		sudo find $$DIR -type d -exec chmod -- 755 {} \; && sudo find $$DIR -type f -exec chmod -- 644 {} \; && \
		printf \"\nfile placed in: \" && readlink -f $$DIR '";
	@echo "✅ Done!"

##
# Dev Server (Vagrant)
#

.PHONY: dev
dev: ## spin up a local dokku server in a vagrant vm
	@cd vendors/dokku && vagrant up

.PHONY: dev_down
dev_down: ## shut down the vagrant vm
	@cd vendors/dokku && vagrant halt

.PHONY: dev_reload
dev_reload: ## restart the vagrant vm (loads Vagrantfile changes), pass --provision to reprovision
	@cd vendors/dokku && vagrant reload

.PHONY: dev_ssh
dev_ssh: ## ssh into the vagraant vm
	@cd vendors/dokku && vagrant ssh

.PHONY: dev_ssh_info
dev_ssh_info: ## get the vagrant vm ssh info
	@cd vendors/dokku && vagrant ssh-config dokku | tee /dev/tty | pbcopy 
	@echo "📋 The SSH settings have been copied to your clipboard!"

.PHONY: dev_destroy
dev_destroy: ## remove the vagrant vm (WARNING: Deletes all files!)
	@cd vendors/dokku && vagrant destroy

##
# Theme 
#

.PHONY: theme_build
theme_build: # run the theme build script on [<local path>] & push to [<hostname or USER@HOST>]:[remote path]
	@cd $(word 1,$(ARGS)) && yarn build
	@make push $(word 1,$(ARGS)) $(word 2,$(ARGS))

##
# https://stackoverflow.com/a/6273809/1826109
%:
	@:
