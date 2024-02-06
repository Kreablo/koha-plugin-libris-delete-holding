# Automatic deletion of Libris holdings records for Koha

[Manual på svenska](docs/manual-sv.md)

## Preparing installation

* Koha-plugins must be activated in koha-conf.xml and the plugin directory must exist and be writable to the koha process.
* The cronjob plugins_nightly must be activated.  This is scheduled by default in cron.daily/koha-common since Koha 20.11.03.

## Installation

1. Upload the plugin koha administration -> manage plugins.
1. Choose the action configure on the plugin (Libris Delete Holding Module).
1. Select mode on the plugin.  For testing QA or STG modes can be used.  For production select the production mode.
1. Add one or more Client ID and Client secret under "Libris credentials".   The credentials can be obtained from Libris customer service.  "Descriptive name" can be choosen arbitrarily and is used for connecting the set of credentials to a branch mapping.
1. Add one or more branch mappings.  Several branchcodes may be mapped to the same sigel.  Each branch mapping must be associated to credentials that grant access to the holdings for the library identified by the sigel.
1. Save the configuration

## Uninstallation

When the plugin is uninstalled, the configration and the status table will be removed from the database.

## Plugin modes

The plugin have three different modes each corresponding to one of the three environments available:

* Produktion, this corresponds to the live holdings under the domain name <https://libris.kb.se/>
* QA, this corresponds to the QA environment under the domain name <https://libris-qa.kb.se/>
* STG, this corresponds to the STG environment under the domain name <https://libris-stg.kb.se/>

For testing the QA or STG modes should be used.

**IMPORTANT!:** If you have a test or development installation of Koha and is regularily importing data from your production installation, you must make sure that this plugin is not running in production mode on your test installation.  As part of the process of importing data to your development environment you should do one of the following:

1. uninstall the plugin in the development environment
1. deactivate the plugin, or,
1. change to QA or STG mode.

# Building the plugin

```sh
> perl Makefile.PL
> make
> make kpzdist
```
