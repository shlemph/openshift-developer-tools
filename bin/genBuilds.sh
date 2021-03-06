#!/bin/bash

OCTOOLSBIN=$(dirname $0)

usage() {
  cat <<-EOF
  Tool to create or update OpenShift build config templates and Jenkins pipeline deployment using
  local and project settings. Also triggers builds that aren't auto-triggered ("builds"
  variable in settings.sh) and tags the images ("images" variable in settings.sh).

  Usage: $0 [ -h -u -c <comp> -k -x ]

  OPTIONS:
  ========
    -h prints the usage for the script
    -c <component> to generate parameters for templates of a specific component
    -l apply local settings and parameters
    -p <profile> load a specific settings profile; setting.<profile>.sh
    -P Use the default settings profile; settings.sh.  Use this flag to ignore all but the default 
       settings profile when there is more than one settings profile defined for a project.        
    -u update OpenShift build configs vs. creating the configs
    -k keep the json produced by processing the template
    -x run the script in debug mode to see what's happening
    -g process the templates and generate the configuration files, but do not create or update them
       automatically set the -k option

    Update settings.sh and settings.local.sh files to set defaults
EOF
exit 1
}

# In case you wanted to check what variables were passed
# echo "flags = $*"
while getopts p:Pc:lukxhg FLAG; do
  case $FLAG in
    c ) export COMP=$OPTARG ;;
    p ) export PROFILE=$OPTARG ;;
    P ) export IGNORE_PROFILES=1 ;;    
    l ) export APPLY_LOCAL_SETTINGS=1 ;;
    u ) export OC_ACTION=replace ;;
    k ) export KEEPJSON=1 ;;
    x ) export DEBUG=1 ;;
    g ) export KEEPJSON=1
        export GEN_ONLY=1
      ;;
    h ) usage ;;
    \?) #unrecognized option - show help
      echo -e \\n"Invalid script option"\\n
      usage
      ;;
  esac
done

# Shift the parameters in case there any more to be used
shift $((OPTIND-1))
# echo Remaining arguments: $@

if [ -f ${OCTOOLSBIN}/settings.sh ]; then
  . ${OCTOOLSBIN}/settings.sh
fi

if [ -f ${OCTOOLSBIN}/ocFunctions.inc ]; then
  . ${OCTOOLSBIN}/ocFunctions.inc
fi

if [ ! -z "${DEBUG}" ]; then
  set -x
fi
# ==============================================================================

for component in ${components}; do
  if [ ! -z "${COMP}" ] && [ ! "${COMP}" = ${component} ]; then
    # Only process named component if -c option specified
    continue
  fi

  echo -e \\n"Configuring the ${TOOLS} environment for ${component} ..."\\n  
  pushd ../${component}/openshift >/dev/null
  compBuilds.sh component
  exitOnError
  popd >/dev/null
done

if [ ! -z "${COMP}" ]; then
  # If only processing one component stop here.
  exit
fi

# Process the Jenkins Pipeline configurations ...
processPipelines.sh

if [ -z ${GEN_ONLY} ]; then
  # ==============================================================================
  # Post Build processing
  echo -e \\n"Builds created. Use the OpenShift Console to monitor the progress in the ${TOOLS} project."
  echo -e \\n"Pause here until the auto triggered builds complete, and then hit a key to continue the script."
  read -n1 -s -r -p "Press a key to continue..." key
  echo -e \\n

  switchProject ${TOOLS}
  exitOnError
  
  for build in ${builds}; do
    echo -e \\n"Manually triggering build of ${build}..."\\n
    oc start-build ${build}
      exitOnError
    echo -e \\n"Use the OpenShift Console to monitor the build in the ${TOOLS} project."
    echo -e "Pause here until the build completes, and then hit a key to continue the script."
    echo -e \\n
    echo -e "If a build hangs take these steps:"
    echo -e " - cancel the instance of the build"
    echo -e " - edit the Build Config YAML and remove the entire 'resources' node; this should only be an issue for local deployments."
    echo -e " - click the Start Build button to restart the build"
    echo -e \\n
    read -n1 -s -r -p "Press a key to continue..." key
    echo -e \\n
  done

  # Tage the images for deployment to the DEV environment ...
  tagProjectImages.sh -s latest -t dev
fi
