# Användarmanual

## Förberedelse

* Koha-plugin:er måste vara aktiverade i koha-conf.xml och plugin-katalogen existera och vara skrivbar för koha-användaren.
* Cronjobbet plugins_nightly måste vara aktiverat. Detta finns som standard med i cron.daily/koha-common sedan Koha 20.11.03.

## Installation

1. Ladda upp pluginen under koha administration -> hantera plugin:er.
1. Välj konfigurera plugin
1. Ställ in läge på pluginen.  I testsyfte kan lägena QA eller STG användas.  För skarp drift används läget "Produktion".
1. Lägg till en eller flera API-nycklar ("client-id" och "client-secret") från Libris som ger access till Libris-XLs API.  "Beskrivande namn" kan väljas fritt och används för att associera biblioteksmappning och API-nyckel i nästa steg.
1. Lägg till en eller flera biblioteksmappningar.  Flera branchcodes kan mappas till samma sigel.  Varje biblioteksmappning måste associeras till rätt API-nyckel för sigelen.
1. Spara konfigurationen

## Avinstallation

Vid avinstallation av plugin:en raderas konfiguration och statustabellen.

## Plugin-lägen

Plugin:en har 3 olika lägen vilka motsvarar de 3 olika miljöer som finns att tillgå hos Libris:

* Produktion, detta är det faktiska Libris-beståndet som finns under domännamnet <https://libris.kb.se/>
* QA, detta är en kopia av beståndet i Libris QA-miljö under domännamnet <https://libris-qa.kb.se/>
* STG, detta är en kopia av beståndet i Libris STG-miljö under domännamnet <https://libris-stg.kb.se/>

I testsyfte skall QA- eller STG-läget användas.

**VIKTIGT!:** Om man har en testmiljö till sin Koha-installation och använder denna plugin, måste man hantera den i sin process för att uppdatera datat i testmiljön genom att endera

1. avinstallera plugin:en,
1. avvaktivera plugin:en eller
1. ändra till QA- eller STG-läge

vid varje uppdatering av datat i testmiljön.

## Fördröjning innan raderingen av bestånd verkställs.

Den faktiska raderingen av bestånd genomförs varje morgon (normalt ca 6:30 om cronjobbet plugins\_nightly är schemalagt under cron.daily). Libris bygger om sökindexet varje natt. Därför kan man förvänta sig en fördröjning på två dagar innan beståndet försvinner från sökresultatet i Libris. Om man har möjlighet att tidigarelägga plugins\_nightly till på kvällen innan Libris bygger om sitt sökinde kan man få beståndet att försvinna från sökresultatet i Libris redan nästa dag.

# Testscenarion

Plugin:ens funktionalitet kan valideras genom nedanstående scenarion.

## SCENARIO 1 EXEMPLARADERING

Leta efter en Libris-post med ett exemplar som tillhör sigeln och radera exemplaret.

Förväntning:

* Beståndsposten skall läggas upp för gallring i tabellen under verktyg -> Verktygsplugin:er -> Libris Delete Holding Module med status 'väntar'
* Nästkommande dag skall beståndsposten vara raderad i Libris och statusen i tabellen skall vara 'klar'

Om det inte finns någon beståndspost för den givna sigeln och den aktuella bibliografiska posten läggs inget in i tabellen.  Därför, kontrollera om det finns någon beståndspost med URL:en:

https://libris-qa.kb.se/_findhold?id=https://libris-qa.kb.se/<libris xl postidentitet>&library=https://libris.kb.se/library/<sigel>

där <libris xl postidentitet> och <sigel> skall bytas ut.

## SCENARIO 2 POSTRADERING

Leta efter en Libris-post med ett exemplar som tillhör sigeln och radera posten

Förväntning:

* Beståndsposten skall läggas upp för gallring i tabellen under verktyg -> Verktygsplugin:er -> Libris Delete Holding Module med status 'väntar'
* Nästkommande dag skall beståndsposten vara raderad i Libris och statusen i tabellen skall vara 'klar'
* I kolumen "Bibliografisk post i Koha" skall det finnas en länk till en sökning efter postens Libris-identitet, vilken inte skall matcha någon post, såtillvida inte det fanns en dublettpost i databasen.

Om det inte finns någon beståndspost för den givna sigeln och den aktuella bibliografiska posten läggs inget in i tabellen.  Därför, kontrollera om det finns någon beståndspost med URL:en:

https://libris-qa.kb.se/_findhold?id=https://libris-qa.kb.se/<libris xl postidentitet>&library=https://libris.kb.se/library/<sigel>

där <libris xl postidentitet> och <sigel> skall bytas ut.

## SCENARIO 3 EXEMPLARRADERING, YTTERLIGARE EXEMPLAR

Leta efter en Libris-post med flera exemplar som tillhör sigeln och radera ett av exemplaret.

Förväntning:

* Ingenting nytt skall läggas upp för gallring i tabellen under verktyg -> Verktygsplugin:er

## SCENARIO 4 EXEMPLARRADERING, ÅNGRA SIG

* Leta efter en Libris-post med ett exemplar som tillhör sigeln och radproduktionslägetaera exemplaret.  Skapa därefter ett nytt exemplar med homebranch satt till en branchcode som motsvarar sigeln.

Förväntning:

* Beståndsposten skall läggas upp för gallring i tabellen under verktyg -> Verktygsplugin:er -> Libris Delete Holding Module med status 'väntar'
* Nästkommande dag skall beståndsposten finnas kvar i Libris och statusen i tabellen skall vara 'avbruten'

I kolumen "Bibliografisk post i Koha" skall det finnas en länk till en sökning efter postens Libris-identitet.

Om det inte finns någon beståndspost för den givna sigeln och den aktuella bibliografiska posten läggs inget in i tabellen.  Därför, kontrollera om det finns någon beståndspost med URL:en:

https://libris-qa.kb.se/_findhold?id=https://libris-qa.kb.se/<libris xl postidentitet>&library=https://libris.kb.se/library/<sigel>

där <libris xl postidentitet> och <sigel> skall bytas ut.

## SCENARIO 5 POSTRADERING, ÅNGRA SIG

Leta efter en Libris-post med ett exemplar som tillhör sigeln och radera posten.  Importera därefter posten på nytt från Libris (ny post från Z39.50/SRU) och skapa ett exemplar med homebranch som mappas till sigeln.

Förväntning:

* Beståndsposten skall läggas upp för gallring i tabellen under verktyg -> Verktygsplugin:er -> Libris Delete Holding Module med status 'väntar'
* I kolumen "Bibliografisk post i Koha" skall det finnas en länk till en sökning efter postens Libris-identitet.
* Nästkommande dag skall beståndsposten finnas kvar i Libris och statusen i tabellen skall vara 'avbruten'

Om det inte finns någon beståndspost för den givna sigeln och den aktuella bibliografiska posten läggs inget in i tabellen.  Därför, kontrollera om det finns någon beståndspost med URL:en:

https://libris-qa.kb.se/_findhold?id=https://libris-qa.kb.se/<libris xl postidentitet>&library=https://libris.kb.se/library/<sigel>

där <libris xl postidentitet> och <sigel> skall bytas ut.

## SCENARIO 6 POSTRADERING SKALL MISSLYCKAS VID ÄNDRING AV LÄGE

OBS! Då detta test innefattar tillgång till produktionsdata skall det genomföras med särskild eftertanke och försktighet!

Om API-nyckeln har tillgång till både produktionsläge och QA- och STG-lägena, ställ in Produktionsläget i i pluginkonfigurationen. Radera därefter ett exemplar som tillhör sigeln.  Ställ sedan in QA-läget  i pluginkonfigurationen.

Förväntning:

* Beståndsposten skall läggas upp för gallring i tabellen under verktyg -> Verktygsplugin:er -> Libris Delete Holding Module med status 'väntar'
* I kolumnerna 'Libris XL-bestånd' och 'Libris XL-post' skall länkarna leda till produktionsmiljön i Libris (under [https://libris.kb.se)](https://libris.kb.se\))
* Nästkommande dag skall beståndsposten finnas kvar i Libris produktionsmiljö och statusen i tabellen skall vara 'misslyckad'.

# Bygga plugin:en

```sh
> perl Makefile.PL
> make
> make kpzdist
```
