FROM ubuntu:20.04

# Default payara ports to expose
# 4848: admin console
# 9009: debug port (JPDA)
# 8080: http
# 8181: https
EXPOSE 4848 9009 8080 8181

ARG PAYARA_VERSION=5.2020.3
ARG PAYARA_PKG=https://search.maven.org/remotecontent?filepath=fish/payara/distributions/payara/${PAYARA_VERSION}/payara-${PAYARA_VERSION}.zip
ARG ADMIN_PASS=admin

# Initialize the configurable environment variables
ENV HOME_DIR=/opt/payara\
    PAYARA_DIR=/opt/payara/appserver\
    SCRIPT_DIR=/opt/payara/scripts\
    CONFIG_DIR=/opt/payara/config\
    DEPLOY_DIR=/opt/payara/deployments\
    PASSWORD_FILE=/opt/payara/passwordFile\
    # Payara Server Domain options (Default Domain:Production, Default user:admin, Default password:admin)
    DOMAIN_NAME=production\
    ADMIN_USER=admin\
    ADMIN_PASSWORD=${ADMIN_PASS} \
    # Utility environment variables
    JVM_ARGS=\
    PAYARA_ARGS=\
    DEPLOY_PROPS=\
    POSTBOOT_COMMANDS=/opt/payara/config/post-boot-commands.asadmin\
    PREBOOT_COMMANDS=/opt/payara/config/pre-boot-commands.asadmin
ENV PATH="${PATH}:${PAYARA_DIR}/bin"

RUN groupadd -g 1000 payara && \
    useradd -u 1000 -M -s /bin/bash -d ${HOME_DIR} payara -g payara && \
    echo payara:payara | chpasswd && \
    mkdir -p ${DEPLOY_DIR} && \
    mkdir -p ${CONFIG_DIR} && \
    mkdir -p ${SCRIPT_DIR} && \
    chown -R payara: ${HOME_DIR} && \
    # Install required packages
    apt-get update && \
    apt-get install -y wget unzip openjdk-11-jre-headless locales && \
    rm -rf /var/lib/apt/lists/* && \
    localedef -i en_DK -c -f UTF-8 -A /usr/share/locale/locale.alias en_DK.UTF-8
ENV LANG en_DK.utf8
    

USER payara
WORKDIR ${HOME_DIR}

RUN wget --no-verbose -O payara.zip ${PAYARA_PKG} && \
    unzip -qq payara.zip -d ./ && \
    mv payara*/ appserver && \
    wget --no-verbose -O ${PAYARA_DIR}/glassfish/domains/production/lib/mysql-connector-java-8.0.19.jar https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.19/mysql-connector-java-8.0.19.jar && \
    # Configure the password file for configuring Payara
    echo "AS_ADMIN_PASSWORD=\nAS_ADMIN_NEWPASSWORD=${ADMIN_PASSWORD}" > /tmp/tmpfile && \
    echo "AS_ADMIN_PASSWORD=${ADMIN_PASSWORD}" >> ${PASSWORD_FILE} && \
    # Configure the payara domain
    ${PAYARA_DIR}/bin/asadmin --user ${ADMIN_USER} --passwordfile=/tmp/tmpfile change-admin-password --domain_name=${DOMAIN_NAME} && \
    ${PAYARA_DIR}/bin/asadmin --user=${ADMIN_USER} --passwordfile=${PASSWORD_FILE} start-domain ${DOMAIN_NAME} && \
    ${PAYARA_DIR}/bin/asadmin --user=${ADMIN_USER} --passwordfile=${PASSWORD_FILE} enable-secure-admin && \    
    for MEMORY_JVM_OPTION in $(${PAYARA_DIR}/bin/asadmin --user=${ADMIN_USER} --passwordfile=${PASSWORD_FILE} list-jvm-options | grep "Xm[sx]"); do\
    ${PAYARA_DIR}/bin/asadmin --user=${ADMIN_USER} --passwordfile=${PASSWORD_FILE} delete-jvm-options $MEMORY_JVM_OPTION;\
    done && \
    ${PAYARA_DIR}/bin/asadmin --user=${ADMIN_USER} --passwordfile=${PASSWORD_FILE} create-jvm-options '-XX\:+UseContainerSupport:-XX\:MaxRAMPercentage=80' && \
    ${PAYARA_DIR}/bin/asadmin --user=${ADMIN_USER} --passwordfile=${PASSWORD_FILE} stop-domain ${DOMAIN_NAME} && \
    # Cleanup unused files
    rm -rf \
    /tmp/tmpFile \
    payara.zip \
    ${PAYARA_DIR}/glassfish/domains/${DOMAIN_NAME}/osgi-cache \
    ${PAYARA_DIR}/glassfish/domains/${DOMAIN_NAME}/logs \
    ${PAYARA_DIR}/glassfish/domains/domain1

# Copy across docker scripts
COPY --chown=payara:payara bin/*.sh ${SCRIPT_DIR}/
RUN mkdir -p ${SCRIPT_DIR}/init.d && \
    chmod +x ${SCRIPT_DIR}/*

CMD ${SCRIPT_DIR}/entrypoint.sh