#!/bin/sh
# usage: sh gen.sh   (run in the project root)
sed -e 's/Bug\.NS/Bug.Pg/g' -e 's/DATALAYER/AshPostgres.DataLayer/' \
    -e 's/LAYERBLOCK(\(.*\))/postgres do\n    table "\1"\n    repo Bug.Repo\n  end/' resources.tmpl > lib/resources_pg.ex
sed -e 's/Bug\.NS/Bug.Ets/g' -e 's/DATALAYER/Ash.DataLayer.Ets/' \
    -e 's/LAYERBLOCK(\(.*\))/ets do\n    private? false\n  end/' resources.tmpl > lib/resources_ets.ex
