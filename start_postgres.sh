#bin/zsh
docker run --name my-postgresql \
    -p 15432:5432 \
    -e POSTGRES_PASSWORD=root \
    -e POSTGRES_DB=test \
    -e POSTGRES_INITDB_WALDIR=/var/lib/postgresql/log \
    -v <host_path>:/var/ltb/postgresql/data \
    -v <host_path>:/var/lib/postgresql/log \
    postgres
