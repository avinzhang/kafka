docker build . -t nivavin/cp-server-connect-with-datagen:7.2.0
docker login --username $DOCKER_USER --password $DOCKER_PASSWORD
docker push nivavin/cp-server-connect-with-datagen:7.2.0


