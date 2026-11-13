# HikariSub official plugins

The plugins HikariSub's own team writes for [HikariSub](https://github.com/altqx/hikari). Each one uses only the [Hikari API](https://github.com/altqx/hikari/blob/main/docs/api.md) that every plugin gets, on the same terms. They are listed in the [marketplace](https://github.com/altqx/hikari-plugins) under the `hikarisub` handle and signed with HikariSub's author key, so HikariSub shows them as "By HikariSub".

## Plugins

| Plugin | Id | What it does |
| --- | --- | --- |
| Macro chains | `hikarisub.macro-chains` | Records a chain of commands and Automation macros with their dialog answers and replays it as one undo step. Imports AegisubChain chains. In progress ([#1093](https://github.com/altqx/hikari/issues/1093)). |
| Keyframe generator | `hikarisub.keyframe-generator` | Finds the video's scene changes and makes keyframes from them. In progress ([#1094](https://github.com/altqx/hikari/issues/1094)). |

## Layout

Each plugin lives in `plugins/<name>/`, where `<name>` is its id without `hikarisub.`:

```
plugins/macro-chains/
  hikari-plugin.json   the manifest
  main.lua             the manifest's main
  lua/                 modules for require
  README.md            shown in the marketplace and the plugin manager
  CHANGELOG.md         one "## <version>" section per release
  tests/run.lua        the plugin's tests, run with LuaJIT from the plugin's folder
```

The package holds everything except `tests/`, `CHANGELOG.md` and dotfiles. The manifest's `publicKey` is the key in [`keys/hikarisub.pub`](keys/hikarisub.pub) (C399EBCEA48BCB30).

## Checks

CI runs on every pull request. For each plugin it:

- checks the manifest against HikariSub's [manifest schema](https://github.com/altqx/hikari/blob/main/docs/schemas/hikari-plugin.schema.json) and the layout above;
- builds the package and runs the registry's own package checks ([`check-package`](https://github.com/altqx/hikari-plugins#for-authors));
- runs `tests/run.lua` with LuaJIT, the runtime HikariSub's plugin helper uses.

Locally:

```sh
git clone https://github.com/altqx/hikari-plugins .registry
pip install -r .registry/requirements.txt
curl -fsSL -o hikari-plugin.schema.json https://raw.githubusercontent.com/altqx/hikari/main/docs/schemas/hikari-plugin.schema.json
export PYTHONPATH=.registry HIKARI_PLUGIN_SCHEMA=$PWD/hikari-plugin.schema.json
python -m unittest discover -s tools/tests -t tools
python tools/release.py check
```

## Releases

Push a tag `<id>-v<version>`, such as `hikarisub.macro-chains-v1.0.0`. The version must be the manifest's, and `CHANGELOG.md` needs a `## 1.0.0` section. The Release workflow then:

1. checks and tests the plugin;
2. builds `<id>-<version>.hikariplugin`;
3. signs it with the `HIKARISUB_MINISIGN_KEY` and `HIKARISUB_MINISIGN_PASSWORD` secrets into `<id>-<version>.hikariplugin.minisig`, refusing any key but `keys/hikarisub.pub`;
4. verifies the signature with minisign and the registry checks;
5. publishes a GitHub release with both files and the changelog section as its notes. The registry picks it up from there.

**Dry run:** run the Release workflow by hand (Actions › Release › Run workflow) with the plugin's folder name. It does steps 1–4 and uploads the signed package as the `signed` artifact, with no tag and no release.

## Licence

MIT, see [LICENSE](LICENSE).
