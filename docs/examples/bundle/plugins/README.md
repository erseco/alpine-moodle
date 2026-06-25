# Bundle plugins directory

This directory illustrates the layout of a Moodle blueprint **bundle**: a
self-contained directory (or ZIP) holding a `blueprint.json` plus the resources
it references.

Place plugin ZIPs here and reference them from `blueprint.json` with a
`bundled` resource descriptor, e.g.:

```json
{ "bundled": "plugins/mod_example.zip" }
```

The example `blueprint.json` in the parent directory expects a file named
`mod_example.zip` here. No binary ZIP is committed to the repository — drop your
own plugin ZIP in this folder, then point `MOODLE_BLUEPRINT_BUNDLE` at the
bundle directory (or zip it up first):

```sh
MOODLE_BLUEPRINT_BUNDLE=/blueprints/bundle/
```
