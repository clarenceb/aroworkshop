# How to load data into the database

Run the `mongoimport` command to import the JSON data files into the database

```sh
mongoimport --host 127.0.0.1 --username userN0E --password MulQxIv2Rvy1QVtN --db sampledb --collection items --type json --file data/items.json --jsonArray
mongoimport --host 127.0.0.1 --username userN0E --password MulQxIv2Rvy1QVtN --db sampledb --collection sites --type json --file data/sites.json --jsonArray
mongoimport --host 127.0.0.1 --username userN0E --password MulQxIv2Rvy1QVtN --db sampledb --collection ratings --type json --file data/ratings.json --jsonArray
```