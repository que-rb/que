Process for building/pushing a new Docker image, because I keep forgetting:

- Install Docker CE, if necessary (https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/)
- Login to Docker, if necessary: sudo docker login
- Update the Dockerfile as necessary.
- Build the dockerfile: sudo docker build .circleci/images
- Find the id of the built image: sudo docker image ls
- Add the tag of the new version to the build image: sudo docker image tag (image id) chanks/que-circleci:0.0.6
- Push new image: sudo docker image push chanks/que-circleci:0.0.6
