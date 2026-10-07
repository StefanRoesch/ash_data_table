#!/bin/sh
sed -e 's/V32\.NS/V32.Pg/g' -e 's/DATALAYER/AshPostgres.DataLayer/' \
    -e 's/LAYERBLOCK(\(.*\))/postgres do\n    table "\1"\n    repo V32.Repo\n  end/' resources.tmpl > lib/resources_pg.ex
sed -e 's/V32\.NS/V32.Ets/g' -e 's/DATALAYER/Ash.DataLayer.Ets/' \
    -e 's/LAYERBLOCK(\(.*\))/ets do\n    private? false\n  end/' resources.tmpl > lib/resources_ets.ex
