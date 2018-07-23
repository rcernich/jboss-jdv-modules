#!/bin/bash

source $JBOSS_HOME/bin/launch/security-ldap.sh 

function prepareEnv() {
  unset SECDOMAIN_NAME
  unset SECDOMAIN_USERS_PROPERTIES
  unset SECDOMAIN_ROLES_PROPERTIES
  unset SECDOMAIN_LOGIN_MODULE
  unset SECDOMAIN_PASSWORD_STACKING
  
  unset JDBC_SECURITY_DOMAIN
  unset ODBC_SECURITY_DOMAIN
  unset ODATA_SECURITY_DOMAIN
  
  unset DEFAULT_SECURITY_DOMAIN

  for prefix in $(echo $SECURITY_DOMAINS | sed "s/,/ /g"); do
    clearDomainEnv $prefix
  done
  unset SECURITY_DOMAINS
  
  unset_security_ldap_env

}

function clearDomainEnv() {
  local prefix=$1

  unset ${prefix}_LOGIN_MODULE_CODE
  unset ${prefix}_LOGIN_MODULE_MODULE

  for option in $(compgen -v | grep -s "${prefix}_MODULE_OPTION_"); do
    unset ${option}
  done
}

function configure() {
  configure_legacy_security_domains
  configure_security_domains
  configure_ldap_security_domain
  set_transport_security_domains

}

function configureEnv() {
  configure
}

function configure_security_domains() {
  if [ -n "$SECURITY_DOMAINS" ]; then
    for domain_prefix in $(echo $SECURITY_DOMAINS | sed "s/,/ /g"); do
      local login_module_name=$(find_env ${domain_prefix}_LOGIN_MODULE_NAME)
      local security_domain="<security-domain name=\"$login_module_name\" cache-type=\"default\">"

      security_domain="$security_domain <authentication>"
      local login_module_code=$(find_env ${domain_prefix}_LOGIN_MODULE_CODE)
      local login_module_module=$(find_env ${domain_prefix}_LOGIN_MODULE_MODULE)
      security_domain="$security_domain <login-module code=\"$login_module_code\" flag=\"required\""
      if [ -n "$login_module_module" ]; then
        security_domain="$security_domain module=\"$login_module_module\""
      fi
      security_domain="$security_domain >"

      local options=$(compgen -v | grep -sE "${domain_prefix}_MODULE_OPTION_NAME_[a-zA-Z]*(_[a-zA-Z]*)*")
     
      for option in $(echo $options); do
        option_name=$(find_env ${option})
        option_value=$(find_env `sed 's/_NAME_/_VALUE_/' <<< ${option}`)
        security_domain="$security_domain <module-option name=\"$option_name\" value=\"$option_value\"/>"
      done
      security_domain="$security_domain </login-module></authentication></security-domain>"
      
      sed -i "s|<!-- ##ADDITIONAL_SECURITY_DOMAINS## -->|${security_domain}<!-- ##ADDITIONAL_SECURITY_DOMAINS## -->|" "$CONFIG_FILE"
    done
  fi  
}

function configure_legacy_security_domains() {
  local usersProperties="\${jboss.server.config.dir}/${SECDOMAIN_USERS_PROPERTIES}"
  local rolesProperties="\${jboss.server.config.dir}/${SECDOMAIN_ROLES_PROPERTIES}"

  # CLOUD-431: Check if provided files are absolute paths
  test "${SECDOMAIN_USERS_PROPERTIES:0:1}" = "/" && usersProperties="${SECDOMAIN_USERS_PROPERTIES}"
  test "${SECDOMAIN_ROLES_PROPERTIES:0:1}" = "/" && rolesProperties="${SECDOMAIN_ROLES_PROPERTIES}"

  local domains="<!-- no additional security domains configured -->"

  if [ -n "$SECDOMAIN_NAME" ]; then
      local login_module=${SECDOMAIN_LOGIN_MODULE:-UsersRoles}
      local realm=""
      local stack=""

      if [ $login_module == "RealmUsersRoles" ]; then
          realm="<module-option name=\"realm\" value=\"ApplicationRealm\"/>"
      fi

      if [ -n "$SECDOMAIN_PASSWORD_STACKING" ]; then
          stack="<module-option name=\"password-stacking\" value=\"useFirstPass\"/>"
      fi
      domains="\
        <security-domain name=\"$SECDOMAIN_NAME\" cache-type=\"default\">\
            <authentication>\
                <login-module code=\"$login_module\" flag=\"required\">\
                    <module-option name=\"usersProperties\" value=\"${usersProperties}\"/>\
                    <module-option name=\"rolesProperties\" value=\"${rolesProperties}\"/>\
                    $realm\
                    $stack\
                </login-module>\
            </authentication>\
        </security-domain>"
  fi

  sed -i "s|<!-- ##ADDITIONAL_SECURITY_DOMAINS## -->|${domains}<!-- ##ADDITIONAL_SECURITY_DOMAINS## -->|" "$CONFIG_FILE"
}

function set_transport_security_domains(){
  DEFAULT_SECURITY_DOMAIN=${DEFAULT_SECURITY_DOMAIN:-teiid-security}
  
  log_info "Default security domain is ${DEFAULT_SECURITY_DOMAIN}"

  sed -i "s|##JDBC_SECURITY_DOMAIN##|${JDBC_SECURITY_DOMAIN:-${DEFAULT_SECURITY_DOMAIN}}|g" ${CONFIG_FILE}
  sed -i "s|##ODBC_SECURITY_DOMAIN##|${ODBC_SECURITY_DOMAIN:-${DEFAULT_SECURITY_DOMAIN}}|g" ${CONFIG_FILE}
  sed -i "s|##ODATA_SECURITY_DOMAIN##|${ODATA_SECURITY_DOMAIN:-${DEFAULT_SECURITY_DOMAIN}}|g" ${CONFIG_FILE}
  
  RESULT_DOMAIN=${JDBC_SECURITY_DOMAIN:-${DEFAULT_SECURITY_DOMAIN}}
  
  log_info "security domain is ${RESULT_DOMAIN}"
}