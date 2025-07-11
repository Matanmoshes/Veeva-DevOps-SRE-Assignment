FROM openjdk:11-jre-slim

# Install Tomcat
ENV CATALINA_HOME /usr/local/tomcat
ENV PATH $CATALINA_HOME/bin:$PATH

# Create tomcat user
RUN groupadd -r tomcat && useradd -r -g tomcat tomcat

# Download and install Tomcat
ENV TOMCAT_VERSION 9.0.80
RUN apt-get update && apt-get install -y wget && \
    wget -O tomcat.tar.gz "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" && \
    tar -xzf tomcat.tar.gz -C /usr/local/ && \
    mv /usr/local/apache-tomcat-${TOMCAT_VERSION} $CATALINA_HOME && \
    rm tomcat.tar.gz && \
    rm -rf $CATALINA_HOME/webapps/ROOT && \
    rm -rf $CATALINA_HOME/webapps/docs && \
    rm -rf $CATALINA_HOME/webapps/examples && \
    rm -rf $CATALINA_HOME/webapps/host-manager && \
    rm -rf $CATALINA_HOME/webapps/manager && \
    chown -R tomcat:tomcat $CATALINA_HOME && \
    chmod +x $CATALINA_HOME/bin/*.sh && \
    rm -rf /var/lib/apt/lists/*

# Copy application WAR file
COPY ROOT.war $CATALINA_HOME/webapps/ROOT.war

# Set up logging
RUN mkdir -p $CATALINA_HOME/logs && \
    chown -R tomcat:tomcat $CATALINA_HOME/logs

# Set environment variables
ENV JAVA_OPTS="-Djava.security.egd=file:/dev/./urandom"
ENV CATALINA_OPTS="-Xmx512m -Xms256m"

# Switch to tomcat user
USER tomcat

# Expose port
EXPOSE 8080

# Start Tomcat
CMD ["catalina.sh", "run"] 