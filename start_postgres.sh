#bin/zsh
docker run --name my-postgresql \
    -p 15432:5432 \
    -e POSTGRES_PASSWORD=root \
    -e POSTGRES_DB=test \
    -e POSTGRES_INITDB_WALDIR=/var/lib/postgresql/log \
    -v /Users/xinwei/docker_data/postgresql/data:/var/ltb/postgresql/data \
    -v /Users/xinwei/docker_data/postgresql/data:/var/lib/postgresql/log \
    postgres
