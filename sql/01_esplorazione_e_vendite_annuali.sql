/* =====================================================================
   PORTFOLIO BI - ADVENTUREWORKS
   File 01 - Esplorazione delle vendite online (fase 1 del progetto)
   ---------------------------------------------------------------------
   Database : AdventureWorksDW2025 su SQL Server 2025
   Canale   : Internet (FactInternetSales = vendite online a clienti privati)
   Scopo    : conoscere i dati prima di costruire le viste e i report.

   Contenuto
     1. Panoramica del database e controlli di base
     2. Andamento annuale
     3. Categorie di prodotto
     4. Approfondimento sulle bici
     5. Cross-selling tra bici e accessori
     6. Stagionalità mensile
     7. Sintesi delle scoperte

   Definizioni valide in tutto il file
     Fatturato     = SalesAmount
     Margine lordo = SalesAmount - TotalProductCost
                     (non considera tasse, spedizioni e costi operativi)
     Margine %     = Margine lordo / Fatturato
     Anni completi = 2011, 2012 e 2013. Il 2010 (3 giorni) e il 2014 (solo gennaio)
                     sono incompleti e restano fuori dai confronti tra anni.

   Nei commenti ai risultati si distinguo i FATTI (si leggono nel risultato)
   dalle IPOTESI (interpretazioni ancora da verificare).
   I numeri citati nei commenti sono i risultati delle query di questo file.
   ===================================================================== */

USE AdventureWorksDW2025;
GO


-- =====================================================================
-- 1. PANORAMICA DEL DATABASE E CONTROLLI DI BASE
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1.1 Quali tabelle contiene il database e quante righe hanno?
-- ---------------------------------------------------------------------
SELECT
    t.name      AS Tabella,
    SUM(p.rows) AS Righe
FROM sys.tables     AS t
JOIN sys.partitions AS p
    ON  t.object_id = p.object_id
    AND p.index_id IN (0, 1)        -- 0 = heap, 1 = indice cluster: ogni riga è contata una volta sola
GROUP BY t.name
ORDER BY t.name;

/*
Il database contiene 31 tabelle. Quelle usate nel progetto:

FATTI
- FactInternetSales        60.398 righe   vendite online a privati, una riga per ogni riga d'ordine:
                                          quantità, prezzo, sconto, costo e ricavo. È la tabella centrale.
- FactResellerSales        60.855 righe   vendite ai rivenditori, con la stessa struttura.
- FactInternetSalesReason  64.515 righe   tabella ponte tra le righe d'ordine online e i motivi d'acquisto.
- FactSalesQuota              163 righe   obiettivi di vendita assegnati ai venditori per periodo.

DIMENSIONI
- DimDate                   3.652 righe   calendario, una riga per giorno.
- DimProduct                  606 righe   prodotti, collegati a DimProductSubcategory (37 righe) e a
                                          DimProductCategory (4: Bikes, Accessories, Clothing, Components).
- DimCustomer              18.484 righe   clienti privati del canale online, collegati a DimGeography (655).
- DimSalesTerritory            11 righe   territori di vendita su tre livelli: regione, paese, gruppo.
- DimPromotion (16), DimReseller (701), DimSalesReason (10)
                                          promozioni, rivenditori, motivi d'acquisto.
*/


-- ---------------------------------------------------------------------
-- 1.2 Che aspetto ha una riga di vendita? (anteprima: bastano 10 righe)
-- ---------------------------------------------------------------------
SELECT TOP (10) *
FROM dbo.FactInternetSales
ORDER BY OrderDateKey, SalesOrderNumber, SalesOrderLineNumber;

/*
Colonne che userò: OrderQuantity (pezzi), SalesAmount (ricavo), TotalProductCost (costo),
ExtendedAmount (importo di listino), DiscountAmount (sconto) e SalesOrderNumber (numero
dell'ordine: un ordine può occupare più righe). TaxAmt (tasse) e Freight (spedizione) sono
colonne separate e restano fuori dal margine lordo.

*/


-- ---------------------------------------------------------------------
-- 1.3 Quanto è grande la tabella e quale periodo copre?
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                            AS RigheVendita,
    COUNT(DISTINCT SalesOrderNumber)    AS NumeroOrdini,
    COUNT(DISTINCT CustomerKey)         AS NumeroClienti,
    COUNT(DISTINCT ProductKey)          AS NumeroProdotti,
    CAST(MIN(OrderDate) AS DATE)        AS PrimoOrdine,
    CAST(MAX(OrderDate) AS DATE)        AS UltimoOrdine
FROM dbo.FactInternetSales;

/*
FATTI
- 60.398 righe di vendita, 27.659 ordini, 18.484 clienti e 158 prodotti venduti
  In media 2,2 righe per ordine (60.398/27.659) e 1,5 ordini per cliente (27.659/18.484).
- Primo ordine il 29 dicembre 2010, ultimo il 28 gennaio 2014: il 2010 copre solo 3 giorni
  e il 2014 solo gennaio. I totali di questi due anni non sono confrontabili con gli altri.
*/


-- ---------------------------------------------------------------------
-- 1.4 Il calendario copre tutto il periodo delle vendite?
-- ---------------------------------------------------------------------

-- Vediamo le prime 10 righe del calendario
SELECT TOP (10) * FROM DimDate;


SELECT
    MIN(FullDateAlternateKey)   AS PrimoGiorno,
    MAX(FullDateAlternateKey)   AS UltimoGiorno,
    COUNT(*)                    AS NumeroGiorni
FROM dbo.DimDate;

/*
FATTO
- Il calendario va dal 1° gennaio 2005 al 31 dicembre 2014: 3.652 giorni, cioè dieci anni
  senza interruzioni. Contiene tutte le date delle vendite.
*/


-- ---------------------------------------------------------------------
-- 1.5 Controllo di qualità: collegando le dimensioni perdo righe di vendita?
--     Con LEFT JOIN la riga di vendita resta sempre; se manca la data, la sottocategoria
--     o la categoria, la colonna della dimensione è NULL e COUNT(colonna) non la conta.
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                        AS RigheVendita,
    COUNT(d.DateKey)                AS RigheConData,
    COUNT(ps.ProductSubcategoryKey) AS RigheConSottocategoria,
    COUNT(pc.ProductCategoryKey)    AS RigheConCategoria
FROM dbo.FactInternetSales          AS f
LEFT JOIN dbo.DimDate               AS d   ON f.OrderDateKey          = d.DateKey
LEFT JOIN dbo.DimProduct            AS p   ON f.ProductKey            = p.ProductKey
LEFT JOIN dbo.DimProductSubcategory AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
LEFT JOIN dbo.DimProductCategory    AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey;

/*
FATTO
I quattro numeri coincidono (60.398): ogni riga di vendita ha la sua data, la sua
sottocategoria e la sua categoria. Nelle query successive posso usare JOIN normali
senza perdere vendite.


SPIEGAZIONE
Può capitare che nella tabella dei prodotti un prodotto abbia ProductSubcategoryKey = NULL.
In questo caso la sua riga non trova corrispondenza nella tabella delle sottocategorie
e, di conseguenza, nemmeno in quella delle categorie.
Lo stesso accade quando ProductSubcategoryKey contiene un valore che non esiste
nella tabella delle sottocategorie (chiave "orfana").

Cosa succede alla riga di vendita dipende dal tipo di JOIN:
- con una JOIN normale (INNER) la riga viene scartata senza alcun avviso
  e i totali risultano sottostimati;
- con una LEFT JOIN la riga resta, ma le colonne di sottocategoria e categoria sono NULL.

Il controllo con LEFT JOIN e COUNT(colonna della dimensione) serve proprio a contare
queste righe: se i conteggi coincidono con COUNT(*), le JOIN normali non perdono vendite.


Supponiamo di unire la tabella delle vendite con la tabella dei prodotti
(ON FactInternetSales.ProductKey = DimProduct.ProductKey) e che, per un certo prodotto, la sottocategoria
in DimProduct sia NULL.

La tabella risultante conterrà comunque la riga di vendita, con l'importo e il nome
del prodotto, ma con la sottocategoria NULL.

Se confrontiamo COUNT(*) con COUNT(ProductSubcategoryKey), il secondo risulterà
inferiore di uno: le righe sono le stesse, ma COUNT(colonna) non conta i valori NULL.
Questa differenza indica quante vendite non hanno una sottocategoria.

Aggiungiamo un ulteriore step. 
Aggiungiamo con una JOIN DimProductSubcategory 
ON DimProduct.ProductSubcategoryKey = DimProductSubcategory.ProductSubcategoryKey
Laddove ProductSubcategoryKey è NULL viene saltata la riga di vendità e i totali
risultano sottostimati.
Stesso discorso se andiamo ad aggiungere la tabella 
Il problema nasce al passaggio successivo: con una JOIN normale verso
DimProductSubcategory (e poi DimProductCategory) la condizione NULL = valore non è
mai vera, quindi la riga di vendita viene scartata senza alcun avviso e i totali
risultano sottostimati.
Stesso discorso se poi aggiungiamo la tabella DimProductCategory.



Possiamo intervenire in diversi modi:
- usare LEFT JOIN verso sottocategoria e categoria, così la riga resta, e sostituire
  i NULL con un'etichetta, ad esempio ISNULL(..., 'Sottocategoria mancante');
- correggere l'anagrafica alla fonte, assegnando al prodotto la sottocategoria giusta;
- escludere le righe, solo come scelta consapevole e documentata.


Nel nostro database i quattro conteggi coincidono (60.398).
Il controllo serve perché in DimProduct la sottocategoria può essere NULL: un prodotto
senza sottocategoria sparirebbe da tutte le query che usano un JOIN normale.
Ciò farebbe perdere delle righe di vendite e si otterrebbe un fatturato sottostimato.
I numeri coincidono, nelle query successive posso usare JOIN senza perdere vendite.


*/


-- =====================================================================
-- 2. ANDAMENTO ANNUALE
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2.1 Come sono andati ordini, fatturato e margine anno per anno?
-- ---------------------------------------------------------------------
SELECT
    d.CalendarYear                                          AS Anno,
    COUNT(DISTINCT d.MonthNumberOfYear)                     AS MesiConVendite,
    COUNT(DISTINCT f.SalesOrderNumber)                      AS NumeroOrdini,      -- un ordine può avere più righe
    SUM(f.OrderQuantity)                                    AS PezziVenduti,
    CAST(SUM(f.SalesAmount)      AS DECIMAL(12,2))          AS Fatturato,         -- Usiamo CAST insieme ad AS DECIMAL(12,2) perché vogliamo solo due cifre decimali. Viceversa, il formato impostato è MONEY con 4 cifre dopo la virgola.
    CAST(SUM(f.TotalProductCost) AS DECIMAL(12,2))          AS Costo,
    CAST(SUM(f.SalesAmount - f.TotalProductCost)
         AS DECIMAL(12,2))                                  AS Margine,           -- ricavi - costi
    CAST(100.0 * SUM(f.SalesAmount - f.TotalProductCost)
         / SUM(f.SalesAmount) AS DECIMAL(5,2))              AS MarginePerc,       -- margine / ricavi
    CAST(SUM(f.SalesAmount)
         / COUNT(DISTINCT f.SalesOrderNumber)
         AS DECIMAL(10,2))                                  AS ValoreMedioOrdine
FROM dbo.FactInternetSales  AS f
JOIN dbo.DimDate            AS d   ON f.OrderDateKey = d.DateKey
GROUP BY d.CalendarYear
ORDER BY Anno;

/*
FATTI
- 2010 e 2014 hanno vendite in un solo mese: sono anni incompleti. I confronti tra anni
  usano solo 2011, 2012 e 2013.
- Controllo: la somma degli ordini per anno (14 + 2.216 + 3.269 + 21.289 + 871 = 27.659)
  coincide con il totale della query 1.3.
- 2011 -> 2012: gli ordini salgono (2.216 -> 3.269, +48%) ma il fatturato scende
  (7,08 -> 5,84 milioni, -17%). Il valore medio dell'ordine passa da 3.192,93 a 1.787,24.
- 2012 -> 2013: gli ordini passano da 3.269 a 21.289 (6,5 volte) e il fatturato quasi
  triplica (16,35 milioni). Il valore medio dell'ordine scende ancora, a 768,08.
- Nel 2011 pezzi e ordini coincidono (2.216): ogni ordine contiene un solo pezzo.
  Nel 2013 i pezzi sono 52.801 su 21.289 ordini, circa 2,5 per ordine.
- Il margine % è stabile nei tre anni completi: 40,20% - 41,56% - 41,37%.
- Nel 2014 il margine % sale al 55,92% e il valore medio dell'ordine crolla a 52,46.

DOMANDE APERTE (le risposte sono nelle sezioni successive)
- Perché nel 2012 ci sono più ordini ma meno fatturato?             -> sezione 4
- Perché nel 2013 gli ordini esplodono e l'ordine medio crolla?     -> sezioni 3 e 5
- Perché il margine % del 2014 è così alto?                         -> sezione 3
*/


-- =====================================================================
-- 3. CATEGORIE DI PRODOTTO
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 Quanto pesa ogni categoria su pezzi, fatturato e margine dell'anno?
-- ---------------------------------------------------------------------

-- Ogni riga di FactInternetSales ha una quantità pari ad uno.
SELECT DISTINCT(OrderQuantity) FROM  dbo.FactInternetSales;


-- Passo 1: totali per anno e categoria
WITH PerCategoria AS (
    SELECT
        d.CalendarYear                              AS Anno,
        pc.EnglishProductCategoryName               AS Categoria,
        COUNT(DISTINCT f.SalesOrderNumber)          AS NumeroOrdini,
        SUM(f.OrderQuantity)                        AS PezziVenduti,
        SUM(f.SalesAmount)                          AS Fatturato,
        SUM(f.SalesAmount - f.TotalProductCost)     AS Margine
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimDate                AS d   ON f.OrderDateKey          = d.DateKey
    JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    GROUP BY d.CalendarYear, pc.EnglishProductCategoryName
)

-- Passo 2: margine % e quote sul totale dell'anno
--          SUM(...) OVER (PARTITION BY Anno) = totale di tutte le categorie dello stesso anno
SELECT
    Anno,
    Categoria,
    NumeroOrdini,
    PezziVenduti,
    CAST(Fatturato AS DECIMAL(12,2))                        AS Fatturato,
    CAST(Margine   AS DECIMAL(12,2))                        AS Margine,
    CAST(100.0 * Margine / Fatturato AS DECIMAL(5,2))       AS MarginePerc,
    CAST(100.0 * PezziVenduti
         / SUM(PezziVenduti) OVER (PARTITION BY Anno)
         AS DECIMAL(5,2))                                   AS QuotaPezziPerc,
    CAST(100.0 * Fatturato
         / SUM(Fatturato) OVER (PARTITION BY Anno)
         AS DECIMAL(5,2))                                   AS QuotaFatturatoPerc,
    CAST(100.0 * Margine
         / SUM(Margine) OVER (PARTITION BY Anno)
         AS DECIMAL(5,2))                                   AS QuotaMarginePerc
FROM PerCategoria
ORDER BY Anno, Fatturato DESC;

/*
FATTI
- Fino al 2011 si vendono solo bici. Accessories e Clothing compaiono nel 2012 con numeri
  minimi (56 e 20 ordini) e decollano nel 2013 (17.378 e 7.125 ordini).
- Nel 2012 si hanno 3.269 ordini che contengono bici e 3.269 biciclette, ciò vuol dire che
  nessuno ha comprato più di una bici nello stesso ordine. 
  Però, analizzando il riepilogo del codice precedente, si scopre che nel 2012 gli ordini
  totali erano 3.269, esattamente quanti gli ordini con bici.
  Quindi, in ogni ordine del 2012 è stata acquistata una bici ed in alcuni casi sono stati
  aggiunti all'ordine anche altri prodotti.
  I primi accessori sono stati venduti solo insieme a una bici.
- 2013: le bici sono il 18,38% dei pezzi ma il 93,93% del fatturato e il 91,90% del margine.
  Gli accessori sono il 65,17% dei pezzi, il 4,09% del fatturato e il 6,18% del margine.
  L'abbigliamento è la categoria più piccola: 16,45% dei pezzi e 1,98% del fatturato.
- Margine %: Accessories 62,60% (identico ogni anno), Bikes 40,20% - 41,55% - 40,48% nei tre
  anni completi, Clothing tra 32,55% e 42,68%.
  Come si legge: 41% vuol dire che su 100 di fatturato ne restano 41 dopo il costo del prodotto.
- 2014: nessuna bici venduta (vedi 3.2).
- Nel 2013 la somma degli ordini per categoria (9.706 + 17.378 + 7.125 = 34.209) supera gli
  ordini totali (21.289): un ordine con una bici e un casco è contato sia in Bikes sia in
  Accessories. I conteggi distinti non si possono sommare tra gruppi.

IPOTESI
- Il business dipende quasi del tutto dalle bici (rischio di concentrazione).
- Gli accessori sembrano un prodotto complementare: molti ordini, poco fatturato.
  Lo verifico nella sezione 5.
- Un margine degli accessori identico ogni anno fa pensare a un ricarico fisso su tutti i
  prodotti della categoria: normale in un dataset di esempio, da segnalare in un'azienda reale.
*/


-- ---------------------------------------------------------------------
-- 3.2 Da quando a quando si vende ogni categoria?
-- ---------------------------------------------------------------------
SELECT
    pc.EnglishProductCategoryName       AS Categoria,
    CAST(MIN(f.OrderDate) AS DATE)      AS PrimaVendita,
    CAST(MAX(f.OrderDate) AS DATE)      AS UltimaVendita
FROM dbo.FactInternetSales      AS f
JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
GROUP BY pc.EnglishProductCategoryName
ORDER BY PrimaVendita;

/*
FATTI
- Bici: prima vendita il 29 dicembre 2010, ultima il 28 dicembre 2013. Nell'ultimo mese di
  dati (fino al 28 gennaio 2014) non si vende nemmeno una bici.
- Accessories e Clothing partono lo stesso giorno, il 28 dicembre 2012, e arrivano fino
  all'ultimo giorno dei dati. I loro numeri del 2012 coprono quindi solo 4 giorni.
- Questo spiega il margine % del 2014 (55,92%): a gennaio 2014 si vendono solo accessori
  (62,60%) e abbigliamento (42,68%). È un effetto mix, non un aumento della redditività.

IPOTESI
- La serie delle bici sembra troncata un mese prima delle altre categorie: dopo tre anni di
  vendite continue è quasi certamente un limite del dataset di esempio. In un'azienda reale
  un mese senza bici sarebbe un'anomalia da segnalare subito.
- Alle bici del 2013 mancano gli ultimi 3 giorni di dicembre: l'effetto sui totali annuali
  dovrebbe essere piccolo.
*/


-- =====================================================================
-- 4. APPROFONDIMENTO SULLE BICI
--    Le bici sono il 94% del fatturato: qui cerco la causa del calo del 2012.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.1 Come cambiano volumi, prezzo medio, margine e quota delle tre linee di bici?
-- ---------------------------------------------------------------------

-- Passo 1: totali per anno e sottocategoria (solo bici, solo anni completi)
WITH Totali AS (
    SELECT
        d.CalendarYear                              AS Anno,
        ps.EnglishProductSubcategoryName            AS Sottocategoria,
        SUM(f.OrderQuantity)                        AS PezziVenduti,
        SUM(f.SalesAmount)                          AS Fatturato,
        SUM(f.SalesAmount - f.TotalProductCost)     AS Margine
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimDate                AS d   ON f.OrderDateKey          = d.DateKey
    JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    WHERE pc.EnglishProductCategoryName = 'Bikes'
      AND d.CalendarYear BETWEEN 2011 AND 2013
    GROUP BY d.CalendarYear, ps.EnglishProductSubcategoryName
),

-- Passo 2: indicatori calcolati sui totali
Indicatori AS (
    SELECT
        Anno,
        Sottocategoria,
        PezziVenduti,
        Fatturato,
        Fatturato / PezziVenduti                                        AS PrezzoMedio,
        100.0 * Margine / Fatturato                                     AS MarginePerc,
        100.0 * Fatturato / SUM(Fatturato) OVER (PARTITION BY Anno)     AS QuotaPerc    -- peso sul fatturato bici dell'anno
    FROM Totali
),

-- Passo 3: accanto a ogni riga, i valori dell'anno precedente della stessa sottocategoria
Confronto AS (
    SELECT
        *,
        LAG(Fatturato)   OVER (PARTITION BY Sottocategoria ORDER BY Anno)   AS FatturatoPrec,
        LAG(MarginePerc) OVER (PARTITION BY Sottocategoria ORDER BY Anno)   AS MarginePercPrec,
        LAG(QuotaPerc)   OVER (PARTITION BY Sottocategoria ORDER BY Anno)   AS QuotaPercPrec
    FROM Indicatori
)

-- Passo 4: risultato con le variazioni (NULL nel primo anno di ogni sottocategoria)
SELECT
    Sottocategoria,
    Anno,
    PezziVenduti,
    CAST(Fatturato AS DECIMAL(12,2))                        AS Fatturato,
    CAST(100.0 * (Fatturato - FatturatoPrec)
         / NULLIF(FatturatoPrec, 0) AS DECIMAL(9,2))        AS VarFatturatoPerc,    -- variazione in %
    CAST(PrezzoMedio AS DECIMAL(10,2))                      AS PrezzoMedio,
    CAST(MarginePerc AS DECIMAL(5,2))                       AS MarginePerc,
    CAST(MarginePerc - MarginePercPrec AS DECIMAL(5,2))     AS VarMarginePP,        -- variazione in punti percentuali
    CAST(QuotaPerc AS DECIMAL(5,2))                         AS QuotaPerc,
    CAST(QuotaPerc - QuotaPercPrec AS DECIMAL(5,2))         AS VarQuotaPP           -- variazione in punti percentuali
FROM Confronto
ORDER BY Sottocategoria, Anno;

/*
FATTI
- Bici vendute in totale: 2.216 -> 3.269 -> 9.706. Nel 2011 ci sono solo Road e Mountain;
  le Touring compaiono nel 2012 con 13 pezzi.
- Quota sul fatturato bici:  Road      81,17% -> 60,87% -> 33,83%
                             Mountain  18,83% -> 38,76% -> 41,28%
                             Touring       -  ->  0,37% -> 24,89%
  Nel 2013 il fatturato è distribuito su tre linee: la concentrazione sulle Road si è ridotta.
- Mountain: margine più alto ogni anno (43,77% -> 46,02% -> 45,45%). Nel 2013 è la prima linea
  per fatturato (6,34 milioni contro 5,20 delle Road) pur vendendo meno pezzi (3.472 contro 4.080).
- Road: il fatturato scende del 38,10% nel 2012 e risale del 46,17% nel 2013. Il prezzo medio
  cala (3.153,85 -> 1.647,30 -> 1.273,55) e il margine passa dal 39,37% al 36,36%
  (-2,37 punti nel solo 2013).
- Anche il prezzo medio delle Mountain scende (3.373,08 -> 2.061,40 -> 1.826,04), ma il
  loro margine % tiene.
- Il margine complessivo delle bici è stabile (40,20% - 41,55% - 40,48%), ma nasconde due
  tendenze opposte: le Road perdono redditività, le Mountain (più redditizie) pesano di più.

ATTENZIONE
- La variazione delle Touring nel 2013 (+17.774%) non è significativa: nel 2012 si sono
  vendute solo 13 Touring.

DOMANDA
- Il prezzo medio cala per gli sconti o perché si vendono modelli più economici?
  Dalla sottocategoria non si capisce: bisogna scendere al singolo modello (4.2 e 4.3).
*/


-- ---------------------------------------------------------------------
-- 4.2 Il prezzo medio delle bici cala perché si fanno sconti?
-- ---------------------------------------------------------------------
SELECT
    d.CalendarYear                                      AS Anno,
    CAST(SUM(f.ExtendedAmount) AS DECIMAL(12,2))        AS ImportoListino,      -- prezzo x quantità, prima degli sconti
    CAST(SUM(f.DiscountAmount) AS DECIMAL(12,2))        AS Sconti,
    CAST(SUM(f.SalesAmount)    AS DECIMAL(12,2))        AS Fatturato,
    MAX(f.UnitPriceDiscountPct)                         AS ScontoMassimoPerc
FROM dbo.FactInternetSales      AS f
JOIN dbo.DimDate                AS d   ON f.OrderDateKey          = d.DateKey
JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
WHERE pc.EnglishProductCategoryName = 'Bikes'
  AND d.CalendarYear BETWEEN 2011 AND 2013
GROUP BY d.CalendarYear
ORDER BY Anno;

/*
FATTO
- Sconti a zero in tutti e tre gli anni (Sconti = 0,00 e ScontoMassimoPerc = 0): importo di
  listino e fatturato coincidono. Sul canale internet le bici sono vendute a prezzo pieno.
*/


-- ---------------------------------------------------------------------
-- 4.3 Sono scesi i prezzi dei singoli modelli, o sono cambiati i modelli venduti?
-- ---------------------------------------------------------------------
SELECT
    ps.EnglishProductSubcategoryName                        AS Sottocategoria,
    p.ModelName                                             AS Modello,
    d.CalendarYear                                          AS Anno,
    SUM(f.OrderQuantity)                                    AS PezziVenduti,
    CAST(SUM(f.SalesAmount) AS DECIMAL(12,2))               AS Fatturato,
    CAST(SUM(f.SalesAmount) / SUM(f.OrderQuantity)
         AS DECIMAL(10,2))                                  AS PrezzoMedio,
    CAST(MIN(f.UnitPrice) AS DECIMAL(10,2))                 AS PrezzoMin,
    CAST(MAX(f.UnitPrice) AS DECIMAL(10,2))                 AS PrezzoMax,
    CAST(100.0 * SUM(f.SalesAmount - f.TotalProductCost)
         / SUM(f.SalesAmount) AS DECIMAL(5,2))              AS MarginePerc
FROM dbo.FactInternetSales      AS f
JOIN dbo.DimDate                AS d   ON f.OrderDateKey          = d.DateKey
JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
WHERE pc.EnglishProductCategoryName = 'Bikes'
  AND d.CalendarYear BETWEEN 2011 AND 2013
GROUP BY ps.EnglishProductSubcategoryName, p.ModelName, d.CalendarYear
ORDER BY Sottocategoria, Modello, Anno;

/*
FATTI
- Nel 2011 il fatturato dipende da due modelli premium: Road-150 (1.544 pezzi a 3.578,27,
  cioè 5,52 milioni) e Mountain-100 (391 pezzi a circa 3.387, cioè 1,32 milioni). Insieme
  fanno il 96,8% del fatturato 2011. Tra gli anni completi si vendono solo nel 2011.
- Nel 2012 al loro posto si vendono modelli meno cari: Mountain-200 (circa 2.065),
  Road-250 (circa 2.279), Road-550-W (circa 1.002) e Road-650 (782,99).
- Il prezzo dei singoli modelli non scende mai: PrezzoMin e PrezzoMax restano uguali o
  salgono. Dove cambiano, l'aumento è del 12%:
      Mountain-200   2.049,10 -> 2.294,99        Road-550-W   1.000,44 -> 1.120,49
      Road-250       2.181,56 -> 2.443,35        Road-650       699,10 ->   782,99
- Sette modelli hanno pochissimi pezzi nel 2012 (da 1 a 11) e volumi pieni nel 2013:
  Mountain-400-W, Mountain-500, Road-350-W, Road-750 e le tre Touring. Sono la nuova gamma,
  con prezzi da 539,99 a 2.384,07: nel 2013 vale 5.529 pezzi su 9.706 (57%).
  La Road-650, invece, nel 2013 non si vende più.
- Nel 2013 il margine % è uguale per tutti i modelli della stessa linea
  (Road 36,36%, Mountain 45,45%, Touring 37,84%).
- Sui modelli Road venduti sia nel 2012 sia nel 2013 il margine % scende anche se il prezzo
  non scende (Road-250 da 38,80% a 36,36%, Road-550-W da 39,42% a 36,36%): il costo medio
  per pezzo è cresciuto più del prezzo medio.

CONCLUSIONE
- Il calo del prezzo medio non dipende da sconti (4.2) né da tagli di prezzo: è un effetto
  mix. Escono i modelli più cari ed entrano modelli più economici. È la risposta alla
  domanda della sezione 2: nel 2012 si vende il 48% di bici in più, ma a un prezzo medio
  di 1.786 contro i 3.193 dell'anno prima.

IPOTESI
- Il catalogo sembra cambiare ogni anno a fine dicembre: i modelli nuovi compaiono con pochi
  pezzi nell'anno di lancio (nel 2011: Mountain-200 4 pezzi, Road-250 15, Road-550-W 2),
  come gli accessori partiti il 28 dicembre 2012.
- Margini identici per linea indicano una regola "costo + ricarico fisso", tipica di un
  dataset di esempio.
*/


-- =====================================================================
-- 5. CROSS-SELLING TRA BICI E ACCESSORI
--    Gli accessori si vendono insieme alle bici? Quanto valore aggiungono?
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5.1 Che tipi di ordine ci sono nel 2013 e quanto valgono?
--     (il 2013 è l'unico anno completo con tutte le categorie in vendita)
-- ---------------------------------------------------------------------

-- Passo 1: una riga per ordine, con il fatturato diviso tra bici e resto
WITH Ordini AS (
    SELECT
        f.SalesOrderNumber                                      AS NumeroOrdine,
        f.CustomerKey                                           AS Cliente,
        SUM(CASE WHEN pc.EnglishProductCategoryName =  'Bikes'
                 THEN f.SalesAmount ELSE 0 END)                 AS FatturatoBici,
        SUM(CASE WHEN pc.EnglishProductCategoryName <> 'Bikes'
                 THEN f.SalesAmount ELSE 0 END)                 AS FatturatoAltro,
        SUM(f.SalesAmount)                                      AS FatturatoOrdine,
        SUM(f.SalesAmount - f.TotalProductCost)                 AS MargineOrdine
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimDate                AS d   ON f.OrderDateKey          = d.DateKey
    JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    WHERE d.CalendarYear = 2013
    GROUP BY f.SalesOrderNumber, f.CustomerKey
),

-- Passo 2: classifico ogni ordine in base al contenuto
OrdiniClassificati AS (
    SELECT
        *,
        CASE
            WHEN FatturatoBici > 0 AND FatturatoAltro > 0 THEN '2. Bici + accessori/abbigliamento'
            WHEN FatturatoBici > 0                        THEN '1. Solo bici'
            ELSE                                               '3. Solo accessori/abbigliamento'
        END                                                     AS TipoOrdine
    FROM Ordini
)

-- Passo 3: indicatori per tipo di ordine
--          SUM(COUNT(*)) OVER () = somma dei conteggi di tutti i tipi, cioè il totale degli ordini
SELECT
    TipoOrdine,
    COUNT(*)                                                AS NumeroOrdini,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaOrdiniPerc,
    COUNT(DISTINCT Cliente)                                 AS NumeroClienti,
    CAST(SUM(FatturatoOrdine) AS DECIMAL(12,2))             AS Fatturato,
    CAST(100.0 * SUM(FatturatoOrdine)
         / SUM(SUM(FatturatoOrdine)) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaFatturatoPerc,
    CAST(AVG(FatturatoOrdine) AS DECIMAL(10,2))             AS ValoreMedioOrdine,
    CAST(AVG(FatturatoBici)   AS DECIMAL(10,2))             AS ValoreMedioParteBici,
    CAST(AVG(FatturatoAltro)  AS DECIMAL(10,2))             AS ValoreMedioParteAltro,
    CAST(100.0 * SUM(MargineOrdine) / SUM(FatturatoOrdine)
         AS DECIMAL(5,2))                                   AS MarginePerc
FROM OrdiniClassificati
GROUP BY TipoOrdine
ORDER BY TipoOrdine;

/*
FATTI (2013)
- Solo accessori/abbigliamento: 11.583 ordini, il 54,41% del totale, ma solo il 3,59% del
  fatturato (valore medio 50,66).
- Bici + accessori/abbigliamento: 8.501 ordini (39,93%) che fanno l'85,11% del fatturato.
- Tra gli ordini con una bici (1.205 + 8.501 = 9.706), l'87,58% contiene anche accessori
  o abbigliamento: l'abbinamento è la regola.
- Un ordine misto vale in media 1.637,09 contro 1.533,47 di un ordine con sola bici
  (+103,62, cioè +6,8%). Di questa differenza solo 47,67 sono accessori e abbigliamento
  (il 2,9% dell'ordine); gli altri 55,95 vengono da bici un po' più care.
- Margine %: 40,08% solo bici, 40,92% ordini misti, 56,31% solo accessori/abbigliamento.
- I clienti non si sommano tra i tre tipi (1.178 + 7.633 + 8.846 = 17.657): lo stesso cliente
  può comparire in più tipi, per esempio con un ordine di sola bici e uno misto.
- Controllo: i tre tipi sommano 21.289 ordini, il totale 2013 della query 2.1.

LETTURA
- L'abbinamento bici + accessori è molto frequente ma aggiunge poco valore all'ordine.
*/


-- ---------------------------------------------------------------------
-- 5.2 Chi compra bici e chi compra solo accessori sono gli stessi clienti?
--     (tutto il periodo)
-- ---------------------------------------------------------------------

-- Passo 1: una riga per ordine: contiene almeno una bici? (1 = sì, 0 = no)
WITH Ordini AS (
    SELECT
        f.SalesOrderNumber                                      AS NumeroOrdine,
        f.CustomerKey                                           AS Cliente,
        MAX(CASE WHEN pc.EnglishProductCategoryName = 'Bikes'
                 THEN 1 ELSE 0 END)                             AS ContieneBici
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    GROUP BY f.SalesOrderNumber, f.CustomerKey
),

-- Passo 2: una riga per cliente: quanti ordini con bici e quanti senza
Clienti AS (
    SELECT
        Cliente,
        SUM(ContieneBici)           AS OrdiniConBici,
        SUM(1 - ContieneBici)       AS OrdiniSenzaBici
    FROM Ordini
    GROUP BY Cliente
)

-- Passo 3: quanti clienti per ogni comportamento
SELECT
    COUNT(*)                                                    AS ClientiTotali,
    SUM(CASE WHEN OrdiniConBici > 0 AND OrdiniSenzaBici = 0
             THEN 1 ELSE 0 END)                                 AS ClientiSoloConBici,
    SUM(CASE WHEN OrdiniConBici = 0 AND OrdiniSenzaBici > 0
             THEN 1 ELSE 0 END)                                 AS ClientiSoloSenzaBici,
    SUM(CASE WHEN OrdiniConBici > 0 AND OrdiniSenzaBici > 0
             THEN 1 ELSE 0 END)                                 AS ClientiConEntrambiITipi
FROM Clienti;

/*
FATTI
- Su 18.484 clienti, 9.132 (49,4%) hanno fatto solo ordini con bici e 9.352 (50,6%) solo
  ordini senza bici.
- ClientiConEntrambiITipi = 0: in tutto il periodo nessun cliente ha fatto sia ordini con
  bici sia ordini senza bici. Le due popolazioni sono separate.
- Quindi nei dati non c'è nessun cliente che parte dagli accessori e poi compra una bici,
  e nessun cliente con bici che torna per comprare solo accessori. L'idea che gli accessori
  servano ad attirare clienti verso le bici qui non trova conferma.

IPOTESI
- Una separazione così netta è molto improbabile nella realtà: con ogni probabilità è una
  caratteristica del dataset di esempio. La riporto come limite dell'analisi.
*/


-- ---------------------------------------------------------------------
-- 5.3 Chi ha iniziato comprando una bici torna a comprare accessori?
-- ---------------------------------------------------------------------

-- Passo 1: una riga per ordine, numerata in ordine di tempo per ogni cliente (1 = primo ordine)
--          Un ordine ha una sola data: MIN serve solo perché siamo dentro un GROUP BY
WITH Ordini AS (
    SELECT
        f.CustomerKey                                           AS Cliente,
        f.SalesOrderNumber                                      AS NumeroOrdine,
        YEAR(MIN(f.OrderDate))                                  AS AnnoOrdine,
        MAX(CASE WHEN pc.EnglishProductCategoryName =  'Bikes'
                 THEN 1 ELSE 0 END)                             AS ContieneBici,
        MAX(CASE WHEN pc.EnglishProductCategoryName <> 'Bikes'
                 THEN 1 ELSE 0 END)                             AS ContieneAltro,
        ROW_NUMBER() OVER (PARTITION BY f.CustomerKey
                           ORDER BY MIN(f.OrderDate), f.SalesOrderNumber)   AS Progressivo
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    GROUP BY f.CustomerKey, f.SalesOrderNumber
),

-- Passo 2: una riga per cliente, con il primo ordine e gli eventuali ritorni
Clienti AS (
    SELECT
        Cliente,
        MIN(AnnoOrdine)                                         AS AnnoPrimoOrdine,
        MAX(CASE WHEN Progressivo = 1 AND ContieneBici = 1
                 THEN 1 ELSE 0 END)                             AS PrimoOrdineConBici,
        MAX(CASE WHEN Progressivo > 1 AND ContieneAltro = 1
                 THEN 1 ELSE 0 END)                             AS TornatoConAccessori
    FROM Ordini
    GROUP BY Cliente
)

-- Passo 3: tra i clienti che hanno iniziato con una bici nel 2011-2012, quanti sono tornati?
SELECT
    COUNT(*)                                                AS ClientiPartitiConBici,
    SUM(TornatoConAccessori)                                AS TornatiConAccessori,
    CAST(100.0 * SUM(TornatoConAccessori) / COUNT(*)
         AS DECIMAL(5,2))                                   AS PercTornatiConAccessori
FROM Clienti
WHERE PrimoOrdineConBici = 1
  AND AnnoPrimoOrdine IN (2011, 2012);

/*
FATTI
- I clienti che hanno iniziato con una bici nel 2011-2012 sono 5.441. Di questi, 4.377
  (80,44%) hanno poi fatto almeno un altro ordine con accessori o abbigliamento.
  Per il risultato 5.2, in quell'ordine c'è sempre anche un'altra bici.
- Considero solo chi ha iniziato nel 2011-2012 perché i clienti del 2013 hanno avuto poco
  tempo per tornare.
- Gli accessori si vendono dal 28 dicembre 2012 e le bici fino al 28 dicembre 2013 (3.2):
  questi ritorni avvengono quindi tutti in quei dodici mesi.

IPOTESI
- Un riacquisto di bici così frequente e concentrato in un solo anno è poco realistico:
  altro segnale che si tratta di dati di esempio.
*/


-- ---------------------------------------------------------------------
-- 5.4 Quali prodotti finiscono più spesso nello stesso ordine di una bici? (2013)
-- ---------------------------------------------------------------------

-- Passo 1: ordini del 2013 che contengono almeno una bici
WITH OrdiniConBici AS (
    SELECT DISTINCT
        f.SalesOrderNumber                                  AS NumeroOrdine
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimDate                AS d   ON f.OrderDateKey          = d.DateKey
    JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    WHERE pc.EnglishProductCategoryName = 'Bikes'
      AND d.CalendarYear = 2013
)

-- Passo 2: le 5 sottocategorie non-bici più presenti in quegli ordini
SELECT TOP (5)
    ps.EnglishProductSubcategoryName                        AS Sottocategoria,
    COUNT(DISTINCT f.SalesOrderNumber)                      AS NumeroOrdini,
    CAST(100.0 * COUNT(DISTINCT f.SalesOrderNumber)
         / (SELECT COUNT(*) FROM OrdiniConBici)
         AS DECIMAL(5,2))                                   AS PercOrdiniConBici   -- su 100 ordini con bici
FROM dbo.FactInternetSales      AS f
JOIN OrdiniConBici              AS o   ON f.SalesOrderNumber      = o.NumeroOrdine      -- solo gli ordini con bici
JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
WHERE pc.EnglishProductCategoryName <> 'Bikes'                                          -- cosa c'è insieme alla bici
GROUP BY ps.EnglishProductSubcategoryName
ORDER BY NumeroOrdini DESC;

/*
FATTI (2013)
- Il casco (Helmets) è l'abbinamento più frequente: è in quasi un ordine con bici su tre
  (3.153 ordini su 9.706, il 32,49%).
- Seguono Bottles and Cages (borracce e portaborracce, 25,45%), Tires and Tubes (copertoni e
  camere d'aria, 21,67%), Jerseys (maglie, 16,18%) e Caps (cappellini, 10,72%).
- Le percentuali non si sommano: lo stesso ordine può contenere più sottocategorie.
*/


-- =====================================================================
-- 6. STAGIONALITÀ MENSILE
-- =====================================================================

-- ---------------------------------------------------------------------
-- 6.1 Come si distribuiscono le vendite nei mesi dell'anno? (2011-2013)
-- ---------------------------------------------------------------------

-- Passo 1: totali per anno e mese
WITH PerMese AS (
    SELECT
        d.CalendarYear                          AS Anno,
        d.MonthNumberOfYear                     AS Mese,
        d.EnglishMonthName                      AS NomeMese,
        COUNT(DISTINCT f.SalesOrderNumber)      AS NumeroOrdini,
        SUM(f.OrderQuantity)                    AS PezziVenduti,
        SUM(f.SalesAmount)                      AS Fatturato
    FROM dbo.FactInternetSales  AS f
    JOIN dbo.DimDate            AS d   ON f.OrderDateKey = d.DateKey
    WHERE d.CalendarYear BETWEEN 2011 AND 2013
    GROUP BY d.CalendarYear, d.MonthNumberOfYear, d.EnglishMonthName
)

-- Passo 2: valore medio dell'ordine e peso del mese sul fatturato dell'anno
SELECT
    Anno,
    Mese,
    NomeMese,
    NumeroOrdini,
    PezziVenduti,
    CAST(Fatturato AS DECIMAL(12,2))                        AS Fatturato,
    CAST(Fatturato / NumeroOrdini AS DECIMAL(10,2))         AS ValoreMedioOrdine,
    CAST(100.0 * Fatturato
         / SUM(Fatturato) OVER (PARTITION BY Anno)
         AS DECIMAL(5,2))                                   AS QuotaSuAnnoPerc      -- un mese "medio" vale 8,33%
FROM PerMese
ORDER BY Anno, Mese;

/*
FATTI
- Giugno è sempre il mese migliore del primo semestre e supera sia maggio sia luglio:
  10,43% - 9,50% - 10,05% del fatturato annuo, contro 7,94% - 6,14% - 7,86% di maggio
  e 8,43% - 7,61% - 8,39% di luglio. Nel 2012 e nel 2013 il mese più alto in assoluto
  è però dicembre (10,69% e 11,46%).
- Ottobre, novembre e dicembre sono sempre sopra la media (tra 9,16% e 11,46%);
  marzo, aprile e maggio sempre sotto (tra 6,14% e 7,94%).
- Dicembre 2011 -> gennaio 2012: il valore medio dell'ordine scende da 3.015,46 a 1.965,73.
  È l'uscita dei modelli premium vista in 4.3.
- Dicembre 2012: per la prima volta i pezzi superano gli ordini (483 contro 355).
  È il lancio di accessori e abbigliamento del 28 dicembre (3.2).
- Gennaio -> febbraio 2013: gli ordini più che raddoppiano (632 -> 1.421) mentre il fatturato
  scende; il valore medio dell'ordine passa da 1.357,10 a 542,82, poi risale fino a 855,09
  a dicembre 2013.

IPOTESI
- Il salto di febbraio 2013 è coerente con l'arrivo degli ordini di soli accessori (5.1),
  che valgono in media 50,66.

CAUTELE
- Nel 2013 crescita e stagionalità si sovrappongono: gennaio vale il 5,25% dell'anno e
  dicembre l'11,46%, ma una parte della differenza è crescita, non stagionalità.
- I clienti sono in entrambi gli emisferi: il picco di giugno va verificato per territorio
  (file 02, analisi geografica).
*/


/* =====================================================================
   7. SINTESI DELLE SCOPERTE
   =====================================================================
   1. Anni confrontabili: solo 2011, 2012 e 2013. In tutto il periodo ci sono 27.659 ordini
      di 18.484 clienti.
   2. Nel 2012 crescono gli ordini (+48%) ma cala il fatturato (-17%). Non dipende da sconti
      (sempre zero) né da tagli di prezzo (dove cambiano, i prezzi salgono del 12%): è un
      effetto mix. Road-150 e Mountain-100, che nel 2011 facevano il 96,8% del fatturato,
      escono dal catalogo e sono sostituiti da modelli meno cari.
   3. Nel 2013 il catalogo si allarga: una gamma di bici più ampia (già comparsa con pochi
      pezzi nel 2012) e, dal 28 dicembre 2012, accessori e abbigliamento. Gli ordini si
      moltiplicano per 6,5, ma le bici restano il 93,93% del fatturato e il 91,90% del margine.
   4. Il margine % è stabile (40,20% - 41,56% - 41,37%), ma tra le bici nasconde due tendenze
      opposte: Road in calo (dal 39,37% al 36,36%), Mountain più redditizie e sempre più pesanti.
   5. Bici e accessori si vendono spesso insieme (87,58% degli ordini con bici), ma l'aggiunta
      vale 47,67 su un ordine medio di 1.637,09 (2,9%). L'abbinamento più frequente è il casco.
   6. Giugno è il mese migliore del primo semestre in tutti e tre gli anni e l'ultimo
      trimestre è sempre sopra la media: da verificare per territorio.

   Limiti del dataset (dati di esempio)
   - Nessuna bici venduta dopo il 28 dicembre 2013.
   - Margini identici per categoria e per linea di prodotto.
   - Clienti di bici (9.132) e clienti di soli accessori (9.352) del tutto separati.
   - L'80,44% dei clienti che comprano una bici nel 2011-2012 ne ricompra una entro il 2013.
   - Nessuna tabella dei resi.

   Prossimi passi
   - File 02: analisi geografica (territori, emisferi, picco di giugno, valuta).
   - Fase 2: trasformare in viste i JOIN che in questo file si ripetono
     (vendite con margine per riga, prodotti con sottocategoria e categoria).
   ===================================================================== */



   /*
   # Portfolio BI AdventureWorks — Riepilogo del progetto

*Aggiornato al 12 novembre 2026. File 01 completo e verificato su SQL Server; analisi geografica (file 02) appena iniziata.*

## Obiettivo
Progetto di portfolio di Business Intelligence per candidature come BI Analyst / Data Analyst (Italia e Stati Uniti).
Strumenti: SQL Server (esplorazione e viste), Power BI (modello a stella, misure DAX, dashboard), Excel (Power Query, pivot, formule).
Output finale: repository GitHub con script, file Power BI ed Excel, screenshot e README; poi aggiornamento del CV.

## Ambiente tecnico
- Server: `.\SQLDEV` — SQL Server 2025 (versione 17.0), SQL Server Management Studio in italiano.
- Database: **AdventureWorksDW2025** (versione data warehouse, schema a stella, 31 tabelle), ripristinato da `AdventureWorksDW2025.bak` scaricato da GitHub Microsoft.
- Cartella di lavoro: `C:\Users\giuse\Desktop\Progetto`.
- Scelta motivata: la versione DW ha già lo schema a stella usato negli uffici BI e si collega in modo pulito a Power BI. Un eventuale secondo progetto potrà partire da AdventureWorks "normale" (gestionale) costruendo lo schema a stella con le viste.

## Stato dei file
- **File 01** (`01_esplorazione_e_vendite_annuali.sql`): **completo e verificato**. 16 query in 7 sezioni: panoramica e controlli, andamento annuale, categorie, bici, cross-selling, stagionalità, sintesi. Tutti i numeri nei commenti vengono dall'esecuzione reale del 12 novembre 2026.
- **File 02** (`02_analisi_geografica.sql`): **in corso**. Scritte le prime due query, risultati non ancora commentati (vedi sezione "Analisi geografica").

## Regole sui dati
- **2010**: solo 29–31 dicembre (14 ordini). **2014**: solo 1–28 gennaio (871 ordini, nessuna bici).
- I confronti tra anni si fanno **solo su 2011, 2012, 2013**. Fatturato 2011–2013 per le riconciliazioni: **29.269.561,47** (tutto il periodo: 29.358.677,23).
- **Bici**: prima vendita 29/12/2010, ultima **28/12/2013** (nessuna bici dal 29 dicembre 2013 alla fine dei dati). **Accessori e abbigliamento**: in vendita dal **28/12/2012**, quindi i loro numeri del 2012 coprono solo 4 giorni.
- Nessuna tabella dei resi in AdventureWorks: l'analisi dei resi è sostituita da motivi d'acquisto (`FactInternetSalesReason` + `DimSalesReason`) e promozioni.
- Margine = margine **lordo** = `SalesAmount − TotalProductCost` (esclusi tasse `TaxAmt`, spedizioni `Freight`, costi operativi).
- Le variazioni di percentuali (margine %, quote) si esprimono in **punti percentuali**; i conteggi distinti (ordini, clienti) **non si sommano** tra categorie o gruppi.
- **Valuta**: nelle prime righe lo stesso prodotto ha lo stesso prezzo con `CurrencyKey` diversi. Ipotesi: importi tutti nella stessa valuta e sommabili tra paesi; da confermare nell'analisi geografica. Nei commenti non scrivere "euro".
- **Qualità dei JOIN**: tutte le 60.398 righe hanno data, sottocategoria e categoria, quindi si possono usare `JOIN` normali (in `DimProduct` la sottocategoria può essere NULL, ma non per i prodotti venduti online).

## Tabelle principali
- Fatti: `FactInternetSales` (60.398 righe, vendite online a privati), `FactResellerSales` (60.855, vendite a rivenditori), `FactSalesQuota` (163), `FactInternetSalesReason` (64.515).
- Dimensioni: `DimDate` (3.652 giorni, 2005–2014), `DimProduct` (606) → `DimProductSubcategory` (37) → `DimProductCategory` (4) (snowflake), `DimCustomer` (18.484) → `DimGeography` (655), `DimSalesTerritory` (11), `DimPromotion` (16), `DimReseller` (701), `DimSalesReason` (10), `DimCurrency` (105).
- Colonne chiave di FactInternetSales: `OrderQuantity`, `UnitPrice`, `ExtendedAmount` (listino), `DiscountAmount`, `TotalProductCost`, `SalesAmount` (ricavo), `SalesOrderNumber` (un ordine può avere più righe), `CustomerKey`, `SalesTerritoryKey`, `CurrencyKey`, `OrderDateKey` (intero AAAAMMGG) e `OrderDate`.

## Scoperte (canale Internet, tutte verificate con il file 01)

### Dimensioni dei dati
60.398 righe di vendita, 27.659 ordini, 18.484 clienti, 158 prodotti venduti; dal 29/12/2010 al 28/01/2014.

### Vendite annuali
| Anno | Ordini | Pezzi | Fatturato | Margine | Margine % | Valore medio ordine |
|---|---|---|---|---|---|---|
| 2011 | 2.216 | 2.216 | 7.075.525,93 | 2.844.063,74 | 40,20 | 3.192,93 |
| 2012 | 3.269 | 3.397 | 5.842.485,20 | 2.428.007,03 | 41,56 | 1.787,24 |
| 2013 | 21.289 | 52.801 | 16.351.550,34 | 6.765.410,97 | 41,37 | 768,08 |

- 2012: ordini +48%, fatturato −17%. 2013: ordini ×6,5, fatturato ×2,8.
- Il margine del 2014 (55,92%) è solo un effetto mix: a gennaio 2014 non si vendono bici, solo accessori (62,60%) e abbigliamento (42,68%).

### Categorie
- 2010–2011 solo bici; accessori e abbigliamento lanciati il **28 dicembre 2012** (nel 2012: 56 e 20 ordini, tutti insieme a una bici), decollano nel 2013.
- 2013: Bikes = 18,38% dei pezzi, **93,93% del fatturato**, 91,90% del margine. Accessories = 65,17% dei pezzi, 4,09% del fatturato, 6,18% del margine. Clothing = 16,45% dei pezzi (la categoria più piccola), 1,98% del fatturato.
- Margine %: Accessories **62,60%** (identico ogni anno), Bikes 40,20 – 41,55 – 40,48, Clothing tra 32,55 e 42,68.
- Nel 2013 la somma degli ordini per categoria (34.209) supera gli ordini totali (21.289): molti ordini contengono più categorie.

### Sottocategorie di bici (quota sul fatturato bici)
| | 2011 | 2012 | 2013 |
|---|---|---|---|
| Road | 81,17% | 60,87% | 33,83% |
| Mountain | 18,83% | 38,76% | 41,28% |
| Touring | — | 0,37% | 24,89% |

- Bici vendute: 2.216 → 3.269 → 9.706.
- **Mountain**: margine più alto ogni anno (43,77 – 46,02 – 45,45%), prima per fatturato nel 2013 (6,34 milioni contro 5,20 delle Road).
- **Road**: prezzo medio 3.153,85 → 1.647,30 → 1.273,55; margine 39,37 → 38,73 → 36,36%.
- **Touring**: 13 pezzi nel 2012, 2.154 nel 2013 (la variazione % non è significativa).
- Il margine bici complessivo, stabile, nasconde due tendenze opposte (Road in calo, Mountain in crescita di peso).

### Modelli di bici
- **Sconti = 0** in tutti gli anni.
- Nel 2011 **Road-150** (1.544 pezzi, 5,52 milioni) e **Mountain-100** (391 pezzi, 1,32 milioni) fanno il **96,8% del fatturato**; tra gli anni completi si vendono solo nel 2011.
- I prezzi dei singoli modelli non scendono mai; dove cambiano salgono del **12%** (Mountain-200, Road-250, Road-550-W, Road-650). Correzione rispetto alla versione precedente: il "+7%" della Road-250 era calcolato sul prezzo medio, non sul prezzo di listino.
- Nuova gamma (Mountain-400-W, Mountain-500, Road-350-W, Road-750, Touring-1000/2000/3000): pochi pezzi nel 2012, poi 5.529 pezzi su 9.706 nel 2013 (57%). La Road-650 esce dopo il 2012.
- Conclusione: il calo del prezzo medio delle bici (3.193 → 1.786 → 1.582) è un **effetto mix**, non sconti né tagli di prezzo.
- Nel 2013 il margine è uniforme per linea (Road 36,36%, Mountain 45,45%, Touring 37,84%): politica "costo + ricarico fisso", tipica del dataset di esempio. Sui modelli Road il margine scende anche se il prezzo non scende: il costo è cresciuto più del prezzo.
- Ipotesi: il catalogo cambia ogni anno a fine dicembre (i modelli nuovi compaiono con pochi pezzi nell'anno di lancio).

### Cross-selling (2013)
| Tipo di ordine | Ordini | % ordini | % fatturato | Valore medio | Margine % |
|---|---|---|---|---|---|
| Solo bici | 1.205 | 5,66 | 11,30 | 1.533,47 | 40,08 |
| Bici + accessori/abbigliamento | 8.501 | 39,93 | 85,11 | 1.637,09 | 40,92 |
| Solo accessori/abbigliamento | 11.583 | 54,41 | 3,59 | 50,66 | 56,31 |

- L'**87,58%** degli ordini con bici contiene anche accessori o abbigliamento, ma l'aggiunta vale solo 47,67 (2,9% dell'ordine).
- Abbinamenti più frequenti negli ordini con bici: Helmets 32,49%, Bottles and Cages 25,45%, Tires and Tubes 21,67%, Jerseys 16,18%, Caps 10,72%.
- Clienti (tutto il periodo): 9.132 con soli ordini con bici, 9.352 con soli ordini senza bici, **0 con entrambi i tipi**. Le due popolazioni sono separate: nei dati gli accessori non portano clienti alle bici.
- Dei 5.441 clienti che hanno iniziato con una bici nel 2011–2012, 4.377 (**80,44%**) sono tornati con un ordine bici + accessori, tutti tra il 28/12/2012 e il 28/12/2013.

### Stagionalità mensile
- **Giugno** è sempre il mese migliore del primo semestre (10,43% / 9,50% / 10,05% del fatturato annuo) e supera maggio e luglio; nel 2012 e nel 2013 il mese più alto in assoluto è dicembre (10,69% e 11,46%).
- **Ottobre–dicembre** sempre sopra la media (tra 9,16% e 11,46%); **marzo–maggio** sempre sotto (tra 6,14% e 7,94%).
- **Gennaio 2012**: il valore medio dell'ordine scende da 3.015,46 a 1.965,73 (uscita dei modelli premium).
- **Dicembre 2012**: per la prima volta pezzi > ordini (483 vs 355), lancio di accessori e abbigliamento.
- **Febbraio 2013**: ordini da 632 a 1.421, valore medio 542,82 (ipotesi: arrivo degli ordini di soli accessori); poi risale a 855,09 a dicembre 2013.
- Cautela: nel 2013 crescita e stagionalità si sovrappongono; mercati in entrambi gli emisferi (da verificare per territorio).

### Limiti del dataset (dati di esempio)
Nessuna bici dopo il 28/12/2013; margini identici per categoria e per linea di prodotto; clienti di bici e di soli accessori del tutto separati; l'80% dei clienti bici 2011–2012 ricompra una bici entro il 2013; nessuna tabella dei resi.

## Analisi geografica (file 02, in corso)
- **Query 1**: struttura dei territori e copertura delle vendite online 2011–2013 (CTE per territorio, `LEFT JOIN` da `DimSalesTerritory`, `COALESCE`, quota con `SUM() OVER ()`).
- **Query 2**: vendite e margini per macro-area (`GROUP BY t.SalesTerritoryGroup`, conteggi distinti ricalcolati sui fatti).
- Risultati non ancora incollati né commentati. Da controllare: riga segnaposto senza vendite in `DimSalesTerritory`, paesi divisi in più regioni, totale 29.269.561,47, differenze di margine % tra aree.
- Da fare dopo: vendite e margini per territorio e anno, stagionalità per emisfero (picco di giugno), verifica della valuta con `CurrencyKey`.

## Tecniche SQL usate finora
JOIN in catena (snowflake), `LEFT JOIN` + `COUNT(colonna)` per controllare le righe perse, GROUP BY su più colonne, `COUNT(DISTINCT)`, `CAST(... AS DECIMAL)`, CTE a passi (`WITH`: prima aggrego, poi calcolo), funzioni finestra `SUM() OVER (PARTITION BY ...)` e `SUM(SUM(...)) OVER ()` per le quote, `LAG()` per le variazioni rispetto all'anno precedente, `ROW_NUMBER()` per numerare gli ordini di ogni cliente, aggregazione condizionale (`SUM` / `MAX` di `CASE WHEN`), `TOP (n)` con `ORDER BY`, sottoquery scalare, `NULLIF` contro la divisione per zero, `COALESCE`, viste di sistema (`sys.tables`, `sys.partitions`, `sys.foreign_key_columns`, `INFORMATION_SCHEMA.COLUMNS`).

## Decisioni di metodo
- **SQL prepara i dati, DAX li analizza**: in Power BI si importano dati riga per riga tramite viste, non tabelle già aggregate; quote, totali e variazioni si calcolano con misure DAX.
- Le query esplorative servono anche per la **riconciliazione** (es. fatturato 2013 in Power BI = 16.351.550,34).
- Calcoli sia in SQL (estrazione, margini, ranking) sia in DAX (crescita anno su anno, % margine, cumulati, Pareto).
- **Struttura degli script**: intestazione con le definizioni, sezioni numerate, una domanda prima di ogni query, sotto il risultato i FATTI separati dalle IPOTESI, sintesi finale. File `.sql` numerati nella cartella Progetto, con una sola estensione.
- Commenti in una sola lingua: per ora italiano (inglese da valutare per il mercato USA).

## Prossimi passi
1. **Analisi geografica** (file 02): commentare i risultati delle query 1 e 2 e completare i punti elencati sopra.
2. **Esplorazione rimanente**: clienti (Pareto 80/20, nuovi vs ricorrenti), motivi d'acquisto, canale rivenditori (verificare se Road-150 e Mountain-100 si vendono ancora lì).
3. **Viste SQL** per Power BI: vendite (con margine per riga), prodotti (con sottocategoria e categoria), clienti (con geografia), calendario (mesi in italiano), territori.
4. **Power BI**: modello a stella, misure DAX, pagine della dashboard (andamento annuale, mix prodotti, stagionalità con annotazioni su gen. 2012 e dic. 2012, geografia, clienti).
5. **Excel**: collegamento alle viste con Power Query, pivot e grafici pivot con slicer, foglio formule (CERCA.X, SOMMA.PIÙ.SE, LET, Pareto), foglio di riepilogo con formattazione condizionale.
6. **GitHub**: script `.sql`, file `.pbix` e `.xlsx`, screenshot, README con le scoperte.
7. **CV**: aggiungere il progetto con risultati concreti.
   */