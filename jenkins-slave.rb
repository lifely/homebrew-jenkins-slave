# Rubydoc: https://rubydoc.brew.sh/Formula.html
class JenkinsSlave < Formula
  desc "Jenkins Slave for macOS"
  homepage "https://jenkins.io/projects/remoting/"

  url "https://repo.jenkins-ci.org/artifactory/releases/org/jenkins-ci/main/remoting/3044.vb_940a_a_e4f72e/remoting-3044.vb_940a_a_e4f72e.jar"
  sha256 "2066d2c91d2be5dbe5a191b0d48cbb04e9a5be2b2294b726ee723f0015cdd2e1"

  depends_on "openjdk@11"
  depends_on "lnav"

  def configure_script_name
    "#{name}-configure"
  end

  def log_file
    var/"log/jenkins-slave/std_out.log"
  end

  def install
    libexec.install "remoting-#{version}.jar"
    libexec.install_symlink "remoting-#{version}.jar" => "remoting.jar"

    bin.write_jar_script libexec / "remoting.jar", name
    (bin + configure_script_name).write configure_script

    # Create the rabbitmq-env.conf file
    remoting_agent_conf = "#{prefix}/agent_options.cfg.template"
    File.write(remoting_agent_conf, remoting_agent_configuration) unless File.exists?(remoting_agent_conf)
  end

  def remoting_agent_configuration
    <<~EOS
      -jnlpUrl
      <jnlp url>
      -secret
      <secret key>
    EOS
  end

  def caveats
    <<~STRING
      WARNING:
        You must configure the daemon first:

      Step 1: Run theconfigure script

        #{configure_script_name} --url "https://my-jenkins.com/computer/agentname/slave-agent.jnlp" \
          --secret "bd38130d1412b54287a00a3750bd100c"

        This is an example. You must change url and secret according to your Jenkins setup.
        For more information about the configuration script run: #{configure_script_name} --help

      Step 2: Start the Jenkins Slave via brew services

        If you want to start on machine boot:

        sudo brew services start #{name}

        If you want to start on login, just do this:

        brew services start #{name}

      Step 3: Verify daemon is running

        sudo launchctl list | grep JenkinsSlave

        Logs can be inspected here: #{log_file}
    STRING
  end

  def configure_script
    <<~STRING
      #!/bin/bash

      set -eu

      PLIST_FILE='#{prefix}/agent_options.cfg'
      JENKINS_URL=""
      JENKINS_SECRET=""
      JENKINS_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

      USAGE="Usage: $(basename "${0}") -u|--url <URL> -s|--secret <SECRET> [-p|--path <PATH>][-h|--help]"
      HELP=$(cat <<- EOT
      This script configures the launchctl configuration for the #{name} service.

      Options:

        -u|--url <URL>          Required URL to the JNLP endpoint of the Jenkins slave.
        -s|--secret <SECRET>    Required secret for the slave node to authenticate against the master.
        -p|--path <PATH>        Optional path to set. Defaults to '/usr/bin:/bin:/usr/sbin:/sbin'.
        -h|--help               Show this help.

      Example:

        #{configure_script_name} --url http://your-jenkins/computer/node/slave-agent.jnlp --secret ******

        #{configure_script_name} --url http://your-jenkins/computer/node/slave-agent.jnlp --secret ****** \
          --path '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
      EOT
      )

      print_help() {
        echo "${USAGE}"
        echo
        echo "${HELP}"
        echo
        echo "Configuration Files available in: #{prefix}/agent_options.cfg"
      }

      echo_err() {
        echo "${1}" >&2
      }

      error() {
        echo_err "Error: ${1}"
      }

      while (( "$#" )); do
        case "${1}" in
          -u|--url)
          if [ -n "${2}" ] && [ "${2:0:1}" != "-" ]; then
              JENKINS_URL="${2}"
              shift 2
          else
              error "Argument for ${1} is missing"
              echo_err "${USAGE}"
              exit 1
          fi
          ;;
        -s|--secret)
          if [ -n "${2}" ] && [ "${2:0:1}" != "-" ]; then
              JENKINS_SECRET="${2}"
              shift 2
          else
              error "Argument for ${1} is missing"
              echo_err "${USAGE}"
              exit 1
          fi
          ;;
        -p|--path)

          ;;
        -d|--download)
          if [ -n "${2}" ] && [ "${2:0:1}" != "-" ]; then
            set +o noclobber
            curl "$2/jnlpJars/agent.jar" > #{prefix}/libexec/agent.jar
            ln -sf #{prefix}/libexec/agent.jar #{prefix}/libexec/remoting.jar
          else
              error "Jenkins URL for ${1} is missing"
              echo_err "${USAGE}"
              exit 1
          fi
          exit 0
          ;;
        -l|--logs)
          lnav #{var}/log/jenkins-slave/std_out.log #{var}/log/jenkins-slave/std_error.log
          exit 0
          ;;
        -h|--help)
          print_help
          exit 0
          ;;
        *)
          error "Unsupported argument: $1!"
          echo_err "${USAGE}"
          ;;
        esac
      done

      if [[ "${JENKINS_URL}" == "" ]]; then
        error "Required argument --url not given!"
        echo_err "${USAGE}"
        exit 2
      fi

      if [[ "${JENKINS_SECRET}" == "" ]]; then
        error "Required argument --secret not given!"
        echo_err "${USAGE}"
        exit 2
      fi

      awk 'NR==2 {$0="'${JENKINS_URL}'"} 1' #{prefix}/agent_options.cfg.template > #{prefix}/agent_options.cfg
      cat #{prefix}/agent_options.cfg > #{prefix}/agent_options.cfg.template
      awk 'NR==4 {$0="'${JENKINS_SECRET}'"} 1' #{prefix}/agent_options.cfg.template > #{prefix}/agent_options.cfg
    STRING
  end

  service do
    run [bin/"jenkins-slave", "@#{opt_prefix}/agent_options.cfg"]
    keep_alive true
    require_root false
    log_path var/"log/jenkins-slave/std_out.log"
    error_log_path var/"log/jenkins-slave/std_error.log"
    run_type :immediate # This should be omitted since it's the default
    process_type :background
    environment_variables PATH: std_service_path_env
    #environment_variables HOMEBREW_PREFIX/"bin:/usr/bin:/bin:/usr/sbin:/sbin"
  end
  ## IF needed https://stackoverflow.com/questions/135688/setting-environment-variables-on-os-x/3756686#3756686
  ## launchctl setenv PATH $PATH before starting service

end
