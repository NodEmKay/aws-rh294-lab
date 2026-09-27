FROM registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel8:latest

USER root

COPY community-general-7.3.0.tar.gz /tmp/community-general-7.3.0.tar.gz

RUN ansible-galaxy collection install \
    /tmp/community-general-7.3.0.tar.gz \
    -p /usr/share/ansible/collections \
    && rm -f /tmp/community-general-7.3.0.tar.gz

USER 1000
