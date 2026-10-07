#!/bin/sh
# results only: no compile noise, no SQL
awk '/^ash [0-9]/{p=1} p' "$1" | grep -v "SQL   :\|^config :ash\|^ash \|created database\|warning\|│\|└─\|^$"
