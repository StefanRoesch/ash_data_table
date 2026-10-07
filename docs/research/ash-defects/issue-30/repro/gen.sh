#!/bin/sh
cd "$(dirname "$0")"
sed -e 's/Ashbug\.NS/Ashbug.Pg/g' -e 's/DATALAYER/AshPostgres.DataLayer/' -e 's/#PG //' resources.tmpl > lib/pg.ex
sed -e 's/Ashbug\.NS/Ashbug.Ets/g' -e 's/DATALAYER/Ash.DataLayer.Ets/' -e '/#PG/d' resources.tmpl > lib/ets.ex
