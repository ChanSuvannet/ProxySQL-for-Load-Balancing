
1. docker exec -it mysql-primary mysql -u root -p (pw: rootpassword)
1. docker exec -it mysql-replica mysql -u root -p


3. mysql -u myuser -pmypassword -h 127.0.0.1 -P 6033 -D mydatabase -e "SELECT * FROM class;"
SELECT * FROM class;