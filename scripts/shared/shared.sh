#!/usr/bin/env bash

## ----------------------------------------------------------------------------
## Colors
## ----------------------------------------------------------------------------

red='\033[1;31m'
green='\033[1;32m'
yellow='\033[1;33m'
purple='\033[1;35m'
blue='\033[1;36m'
nocolor='\033[0m'
gray='\033[1;30m'
light_gray='\033[0;37m'

## ----------------------------------------------------------------------------
## Separator
## ----------------------------------------------------------------------------
export SEP="-------------------------------------------------------------------------------"

## Just for cosmetic reasons ...
function end {
  echo "$SEP"
}

function load_env {
  echo "$SEP"
  echo -e "${green}> Loading local environment variables ...${nocolor}\n"
  if [ ! -f $(pwd)/.env.sh ]; then
      echo -e "${red}File .env.sh not found!${nocolor}\n"
  fi
  source $(pwd)/.env.sh
}

## Load environment variables form a file.
## Example:
##  load_env_from_file "./aws-kops.env"
function load_env_from_file {

  load_from=("$@")

  echo -e "${green}> Loading environment variables from  '${load_from}'${nocolor}\n"

  export $(grep -v '^#' ${load_from} | xargs)
}

function validate_required_env_vars {
  req_env_vars=("$@")

  echo "$SEP"
  echo -e "${green}> Validating necessary environment variables ...${nocolor}\n"

  ## ----------------------------------------------------------------------------
  ## Validate if all required environment variables are set
  ##      - if one fails, echo and exit.
  ## ----------------------------------------------------------------------------
  for var_name in "${req_env_vars[@]}"
  do
    if [ -z "$(eval "echo \$$var_name")" ]; then
      echo -e "${red}\t- Missing environment variable $var_name${nocolor}\n"
      exit 1
    else
      echo -e "     [OK] $var_name (=$(eval "echo \$$var_name"))"
    fi
  done
  echo
}

function show_time () {
    num=$1
    min=0
    hour=0
    day=0
    if((num>59));then
        ((sec=num%60))
        ((num=num/60))
        if((num>59));then
            ((min=num%60))
            ((num=num/60))
            if((num>23));then
                ((hour=num%24))
                ((day=num/24))
            else
                ((hour=num))
            fi
        else
            ((min=num))
        fi
    else
        ((sec=num))
    fi
    echo "$day"d "$hour"h "$min"m "$sec"s
}
