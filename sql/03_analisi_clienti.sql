/* =====================================================================
   PORTFOLIO BI - ADVENTUREWORKS
   File 03 - Analisi dei clienti del canale online
   ---------------------------------------------------------------------
   Database : AdventureWorksDW2025 su SQL Server 2025
   Canale   : Internet (FactInternetSales, DimCustomer)
   Scopo    : capire quanto è concentrato il fatturato sui clienti, quanti tornano
              a comprare, chi sono i clienti che spendono di più e perché comprano.

   Contenuto
     1. Panoramica dei clienti
     2. Concentrazione del fatturato (Pareto)
     3. Clienti nuovi e clienti ricorrenti
     4. Profilo dei clienti
     5. Motivi d'acquisto
     6. Sintesi delle scoperte

   Definizioni: le stesse del file 01. Le sezioni 1, 2, 4 e 5 guardano tutto il periodo
   (29/12/2010 - 28/01/2014, fatturato totale 29.358.677,23); la sezione 3 confronta
   gli anni completi 2011-2013.

   I numeri citati nei commenti sono i risultati delle query di questo file.
   ===================================================================== */

USE AdventureWorksDW2025;
GO


-- =====================================================================
-- 1. PANORAMICA DEI CLIENTI
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1.1 Tutti i clienti in anagrafica hanno comprato almeno una volta?
-- ---------------------------------------------------------------------

-- Passo 1: clienti presenti nelle vendite
WITH ClientiConAcquisti AS (
    SELECT DISTINCT
        f.CustomerKey
    FROM dbo.FactInternetSales AS f
)

-- Passo 2: confronto con l'anagrafica (LEFT JOIN: resta anche chi non ha mai comprato)
SELECT
    COUNT(*)                                AS ClientiInAnagrafica,
    COUNT(a.CustomerKey)                    AS ClientiConAcquisti,
    COUNT(*) - COUNT(a.CustomerKey)         AS ClientiSenzaAcquisti
FROM dbo.DimCustomer            AS c
LEFT JOIN ClientiConAcquisti    AS a   ON c.CustomerKey = a.CustomerKey;

/*
FATTO
- Tutti i 18.484 clienti in anagrafica hanno comprato almeno una volta: DimCustomer contiene
  solo clienti del canale online, nessun nominativo senza acquisti.
*/


-- ---------------------------------------------------------------------
-- 1.2 Quanti ordini fa un cliente? Quanto pesa chi compra più volte?
-- ---------------------------------------------------------------------

-- Passo 1: una riga per cliente
WITH Clienti AS (
    SELECT
        f.CustomerKey                               AS Cliente,
        COUNT(DISTINCT f.SalesOrderNumber)          AS NumeroOrdini,
        SUM(f.SalesAmount)                          AS Fatturato
    FROM dbo.FactInternetSales AS f
    GROUP BY f.CustomerKey
),

-- Passo 2: classe del cliente in base al numero di ordini
ClientiClassificati AS (
    SELECT
        *,
        CASE
            WHEN NumeroOrdini = 1 THEN '1 ordine'
            WHEN NumeroOrdini = 2 THEN '2 ordini'
            WHEN NumeroOrdini = 3 THEN '3 ordini'
            ELSE                       '4+ ordini'
        END                                         AS ClasseOrdini
    FROM Clienti
)

-- Passo 3: clienti e fatturato per classe
SELECT
    ClasseOrdini,
    COUNT(*)                                                AS NumeroClienti,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaClientiPerc,
    CAST(SUM(Fatturato) AS DECIMAL(12,2))                   AS Fatturato,
    CAST(100.0 * SUM(Fatturato)
         / SUM(SUM(Fatturato)) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaFatturatoPerc,
    CAST(AVG(Fatturato) AS DECIMAL(10,2))                   AS FatturatoMedioPerCliente
FROM ClientiClassificati
GROUP BY ClasseOrdini
ORDER BY ClasseOrdini;

/*
FATTI
- Controlli: i clienti sommano 18.484 e il fatturato 29.358.677,21 (2 centesimi di
  arrotondamento rispetto al totale del periodo).
- Il 62,86% dei clienti ha fatto un solo ordine e vale il 22,98% del fatturato
  (580,77 a testa).
- Il 37,14% dei clienti con due o più ordini fa il 77,02% del fatturato. Il gruppo più
  importante è quello con 2 ordini: 29,51% dei clienti, 54,43% del fatturato.
- Chi ha fatto 4 o più ordini spende in media meno di chi ne ha fatti 3
  (3.434,65 contro 4.966,15).

IPOTESI
- I clienti con molti ordini potrebbero essere in buona parte clienti di soli accessori:
  tanti ordini piccoli. Si verifica separando i clienti con bici dagli altri.
*/


-- =====================================================================
-- 2. CONCENTRAZIONE DEL FATTURATO (PARETO)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2.1 Il 20% dei clienti fa l'80% del fatturato?
--     Ordino i clienti dal più grande al più piccolo e li divido in 10 gruppi uguali (decili).
-- ---------------------------------------------------------------------

-- Passo 1: fatturato di ogni cliente
WITH Clienti AS (
    SELECT
        f.CustomerKey                               AS Cliente,
        SUM(f.SalesAmount)                          AS Fatturato
    FROM dbo.FactInternetSales AS f
    GROUP BY f.CustomerKey
),

-- Passo 2: NTILE(10) assegna a ogni cliente un decile (1 = il 10% che spende di più)
Decili AS (
    SELECT
        Cliente,
        Fatturato,
        NTILE(10) OVER (ORDER BY Fatturato DESC)    AS Decile
    FROM Clienti
),

-- Passo 3: totali per decile
PerDecile AS (
    SELECT
        Decile,
        COUNT(*)                                    AS NumeroClienti,
        SUM(Fatturato)                              AS Fatturato,
        MIN(Fatturato)                              AS SpesaMinima,
        MAX(Fatturato)                              AS SpesaMassima
    FROM Decili
    GROUP BY Decile
)

-- Passo 4: quota di ogni decile e quota cumulata (somma progressiva dal decile 1 in giù)
SELECT
    Decile,
    NumeroClienti,
    CAST(SpesaMinima  AS DECIMAL(10,2))                     AS SpesaMinima,
    CAST(SpesaMassima AS DECIMAL(10,2))                     AS SpesaMassima,
    CAST(Fatturato    AS DECIMAL(12,2))                     AS Fatturato,
    CAST(100.0 * Fatturato / SUM(Fatturato) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaFatturatoPerc,
    CAST(100.0 * SUM(Fatturato) OVER (ORDER BY Decile ROWS UNBOUNDED PRECEDING)
         / SUM(Fatturato) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaCumulataPerc
FROM PerDecile
ORDER BY Decile;

/*
FATTI
- La regola 80/20 qui non vale alla lettera: il primo 20% dei clienti fa il 66,42% del
  fatturato; per arrivare all'80% serve il 30% (83,17%).
- La metà dei clienti fa quasi tutto: i primi 5 decili arrivano al 98,05%, gli ultimi 5
  (9.240 clienti) valgono l'1,95%.
- Il primo decile (1.849 clienti, da 4.827,10 a 13.295,38 di spesa) fa da solo il 40,28%.
- Dal quinto al sesto decile la spesa crolla: nel quinto si va da 1.155,48 a 268,25,
  nel sesto non si superano i 267,84.

LETTURA
- La concentrazione ricalca la separazione vista nel file 01: 9.132 clienti hanno comprato
  bici e 9.352 solo accessori. La metà bassa della classifica (9.240 clienti) ha quasi
  lo stesso numero di clienti del gruppo di soli accessori.

IPOTESI
- Tra i soli clienti con bici la concentrazione è molto più bassa: il primo decile equivale
  a circa il 20% dei clienti con bici e fa il 40% del fatturato, lontano dall'80/20.

DECISIONE
- Nella dashboard il Pareto va letto insieme alla distinzione "cliente con bici / solo
  accessori", che è la segmentazione più importante di questo dataset.
*/


-- =====================================================================
-- 3. CLIENTI NUOVI E CLIENTI RICORRENTI
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 Ogni anno, quanti clienti sono nuovi e quanti avevano già comprato? (2011-2013)
--     Nuovo = il suo primo ordine in assoluto è in quell'anno.
-- ---------------------------------------------------------------------

-- Passo 1: anno del primo ordine di ogni cliente (su tutto il periodo, 2010 compreso)
WITH PrimoOrdine AS (
    SELECT
        f.CustomerKey                               AS Cliente,
        MIN(d.CalendarYear)                         AS AnnoPrimoOrdine
    FROM dbo.FactInternetSales  AS f
    JOIN dbo.DimDate            AS d   ON f.OrderDateKey = d.DateKey
    GROUP BY f.CustomerKey
),

-- Passo 2: una riga per cliente e anno in cui ha comprato
ClientiAnno AS (
    SELECT
        d.CalendarYear                              AS Anno,
        f.CustomerKey                               AS Cliente,
        SUM(f.SalesAmount)                          AS Fatturato
    FROM dbo.FactInternetSales  AS f
    JOIN dbo.DimDate            AS d   ON f.OrderDateKey = d.DateKey
    WHERE d.CalendarYear BETWEEN 2011 AND 2013
    GROUP BY d.CalendarYear, f.CustomerKey
)

-- Passo 3: clienti e fatturato, divisi tra nuovi e ricorrenti
SELECT
    a.Anno,
    COUNT(*)                                                        AS ClientiAttivi,
    SUM(CASE WHEN p.AnnoPrimoOrdine = a.Anno THEN 1 ELSE 0 END)     AS ClientiNuovi,
    SUM(CASE WHEN p.AnnoPrimoOrdine < a.Anno THEN 1 ELSE 0 END)     AS ClientiRicorrenti,
    CAST(100.0 * SUM(CASE WHEN p.AnnoPrimoOrdine < a.Anno THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2))                                AS QuotaRicorrentiPerc,
    CAST(SUM(CASE WHEN p.AnnoPrimoOrdine = a.Anno
                  THEN a.Fatturato ELSE 0 END) AS DECIMAL(12,2))    AS FatturatoNuovi,
    CAST(SUM(CASE WHEN p.AnnoPrimoOrdine < a.Anno
                  THEN a.Fatturato ELSE 0 END) AS DECIMAL(12,2))    AS FatturatoRicorrenti,
    CAST(100.0 * SUM(CASE WHEN p.AnnoPrimoOrdine < a.Anno
                          THEN a.Fatturato ELSE 0 END)
         / SUM(a.Fatturato) AS DECIMAL(5,2))                        AS QuotaFatturatoRicorrentiPerc
FROM ClientiAnno    AS a
JOIN PrimoOrdine    AS p   ON a.Cliente = p.Cliente
GROUP BY a.Anno
ORDER BY a.Anno;

/*
FATTI
- Controlli: nuovi + ricorrenti danno il fatturato annuo del file 01 (5.842.485,20 nel 2012
  e 16.351.550,34 nel 2013).
- Nel 2011 e nel 2012 quasi nessuno torna: 0 clienti ricorrenti nel 2011 e 30 nel 2012 (0,92%).
- Nel 2013 i ricorrenti sono 4.906, il 28,15% dei clienti attivi, ma fanno il 63,97% del
  fatturato: 2.132,25 a testa contro 470,39 dei clienti nuovi.
- I clienti arrivati prima del 2013 sono 5.455 (14 + 2.216 + 3.225): nel 2013 ne torna
  l'89,94%.
- Il fatturato dei clienti nuovi resta quasi fermo: 7,08 milioni nel 2011, 5,78 nel 2012,
  5,89 nel 2013. La crescita del 2013 (+10,51 milioni sul 2012) è pari al fatturato dei
  clienti ricorrenti (10,46 milioni).

IPOTESI
- Che il 90% dei clienti torni tutto nello stesso anno, dopo due anni senza riacquisti,
  non è realistico: è un'altra caratteristica del dataset di esempio. In un'azienda reale
  chiederei se nel 2013 c'è stata una campagna rivolta ai vecchi clienti.
*/


-- =====================================================================
-- 4. PROFILO DEI CLIENTI
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.1 Che lavoro fanno i clienti, e quali professioni comprano più bici?
-- ---------------------------------------------------------------------

-- Passo 1: una riga per cliente: quanto ha speso e se ha comprato almeno una bici
WITH Clienti AS (
    SELECT
        f.CustomerKey                                           AS Cliente,
        SUM(f.SalesAmount)                                      AS Fatturato,
        MAX(CASE WHEN pc.EnglishProductCategoryName = 'Bikes'
                 THEN 1 ELSE 0 END)                             AS HaCompratoBici
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    GROUP BY f.CustomerKey
)

-- Passo 2: indicatori per professione
SELECT
    c.EnglishOccupation                                     AS Professione,
    COUNT(*)                                                AS NumeroClienti,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaClientiPerc,
    CAST(AVG(c.YearlyIncome) AS DECIMAL(10,2))              AS RedditoMedio,
    CAST(100.0 * SUM(k.HaCompratoBici) / COUNT(*)
         AS DECIMAL(5,2))                                   AS PercConBici,
    CAST(SUM(k.Fatturato) AS DECIMAL(12,2))                 AS Fatturato,
    CAST(SUM(k.Fatturato) / COUNT(*) AS DECIMAL(10,2))      AS FatturatoPerCliente
FROM Clienti            AS k
JOIN dbo.DimCustomer    AS c   ON k.Cliente = c.CustomerKey
GROUP BY c.EnglishOccupation
ORDER BY FatturatoPerCliente DESC;

/*
FATTI
- Controllo: le cinque professioni sommano 18.484 clienti.
- La quota di clienti con bici cambia poco tra le professioni: dal 43,62% (Manual) al
  55,98% (Clerical), contro una media generale del 49,40%.
- Il fatturato per cliente va da 1.198,81 (Manual) a 1.794,92 (Professional): 1,5 volte.
- Clerical ha un reddito medio basso (30.710) ma la quota di clienti con bici più alta
  e una spesa per cliente (1.600,00) superiore a Skilled Manual, che guadagna di più.

LETTURA
- La professione da sola spiega poco: non c'è un gruppo che compra molto più degli altri.
*/


-- ---------------------------------------------------------------------
-- 4.2 Chi guadagna di più compra più bici e spende di più?
-- ---------------------------------------------------------------------

-- Passo 1: una riga per cliente: quanto ha speso e se ha comprato almeno una bici
WITH Clienti AS (
    SELECT
        f.CustomerKey                                           AS Cliente,
        SUM(f.SalesAmount)                                      AS Fatturato,
        MAX(CASE WHEN pc.EnglishProductCategoryName = 'Bikes'
                 THEN 1 ELSE 0 END)                             AS HaCompratoBici
    FROM dbo.FactInternetSales      AS f
    JOIN dbo.DimProduct             AS p   ON f.ProductKey            = p.ProductKey
    JOIN dbo.DimProductSubcategory  AS ps  ON p.ProductSubcategoryKey = ps.ProductSubcategoryKey
    JOIN dbo.DimProductCategory     AS pc  ON ps.ProductCategoryKey   = pc.ProductCategoryKey
    GROUP BY f.CustomerKey
),

-- Passo 2: fascia di reddito annuo dichiarato dal cliente
ClientiConFascia AS (
    SELECT
        k.Cliente,
        k.Fatturato,
        k.HaCompratoBici,
        CASE
            WHEN c.YearlyIncome <  40000 THEN '1. meno di 40.000'
            WHEN c.YearlyIncome <  70000 THEN '2. da 40.000 a 69.999'
            WHEN c.YearlyIncome < 100000 THEN '3. da 70.000 a 99.999'
            ELSE                              '4. da 100.000 in su'
        END                                                     AS FasciaReddito
    FROM Clienti            AS k
    JOIN dbo.DimCustomer    AS c   ON k.Cliente = c.CustomerKey
)

-- Passo 3: indicatori per fascia
SELECT
    FasciaReddito,
    COUNT(*)                                                AS NumeroClienti,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaClientiPerc,
    CAST(100.0 * SUM(HaCompratoBici) / COUNT(*)
         AS DECIMAL(5,2))                                   AS PercConBici,
    CAST(SUM(Fatturato) AS DECIMAL(12,2))                   AS Fatturato,
    CAST(100.0 * SUM(Fatturato)
         / SUM(SUM(Fatturato)) OVER ()
         AS DECIMAL(5,2))                                   AS QuotaFatturatoPerc,
    CAST(SUM(Fatturato) / COUNT(*) AS DECIMAL(10,2))        AS FatturatoPerCliente
FROM ClientiConFascia
GROUP BY FasciaReddito
ORDER BY FasciaReddito;

/*
FATTI
- Controllo: le quattro fasce sommano 18.484 clienti.
- La quota di clienti con bici è quasi uguale in tutte le fasce (tra 44,88% e 51,62%):
  il reddito non decide se un cliente compra una bici.
- La spesa per cliente invece cresce con il reddito: da 1.215,07 sotto i 40.000 a 2.194,71
  sopra i 100.000 (1,8 volte).
- La fascia più alta è l'11,89% dei clienti e fa il 16,43% del fatturato.

IPOTESI
- A parità di quota di clienti con bici, chi guadagna di più compra bici più care o ne
  compra più di una. Si può verificare con il prezzo medio delle bici per fascia.

DECISIONE
- Nella vista clienti porto professione e reddito (con la fascia), oltre alla geografia.
*/


-- =====================================================================
-- 5. MOTIVI D'ACQUISTO
--    FactInternetSalesReason è una tabella ponte: una riga d'ordine può avere
--    nessun motivo, un motivo o più motivi.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5.1 Quante righe d'ordine hanno un motivo d'acquisto, e quante ne hanno più di uno?
-- ---------------------------------------------------------------------

-- Passo 1: numero di motivi per ogni riga d'ordine (0 se non ne ha)
WITH MotiviPerRiga AS (
    SELECT
        f.SalesOrderNumber,
        f.SalesOrderLineNumber,
        COUNT(r.SalesReasonKey)                     AS NumeroMotivi
    FROM dbo.FactInternetSales              AS f
    LEFT JOIN dbo.FactInternetSalesReason   AS r
        ON  f.SalesOrderNumber     = r.SalesOrderNumber
        AND f.SalesOrderLineNumber = r.SalesOrderLineNumber
    GROUP BY f.SalesOrderNumber, f.SalesOrderLineNumber
)

-- Passo 2: quante righe per numero di motivi
SELECT
    COUNT(*)                                                AS RigheVendita,
    SUM(CASE WHEN NumeroMotivi = 0 THEN 1 ELSE 0 END)       AS RigheSenzaMotivo,
    SUM(CASE WHEN NumeroMotivi = 1 THEN 1 ELSE 0 END)       AS RigheConUnMotivo,
    SUM(CASE WHEN NumeroMotivi > 1 THEN 1 ELSE 0 END)       AS RigheConPiuMotivi,
    SUM(NumeroMotivi)                                       AS RigheTabellaPonte
FROM MotiviPerRiga;

/*
FATTI
- Controllo: le righe della tabella ponte sono 64.515, come nel file 01.
- Il 72,67% delle righe d'ordine ha un solo motivo, il 16,69% ne ha più di uno (in media 2)
  e il 10,64% non ne ha nessuno.
- Quindi un JOIN diretto tra vendite e motivi cambia i totali: perde le 6.429 righe senza
  motivo e conta più volte le 10.078 righe con più motivi.
*/


-- ---------------------------------------------------------------------
-- 5.2 Quali sono i motivi d'acquisto più frequenti?
--     Attenzione: una riga con due motivi è contata in entrambi, quindi
--     ordini e fatturato dei motivi non si possono sommare tra loro.
-- ---------------------------------------------------------------------
SELECT
    sr.SalesReasonReasonType                                AS TipoMotivo,
    sr.SalesReasonName                                      AS Motivo,
    COUNT(*)                                                AS RigheVendita,
    COUNT(DISTINCT f.SalesOrderNumber)                      AS NumeroOrdini,
    CAST(100.0 * COUNT(DISTINCT f.SalesOrderNumber)
         / (SELECT COUNT(DISTINCT SalesOrderNumber) FROM dbo.FactInternetSales)
         AS DECIMAL(5,2))                                   AS PercSuTuttiGliOrdini,
    CAST(SUM(f.SalesAmount) AS DECIMAL(12,2))               AS FatturatoCollegato
FROM dbo.FactInternetSalesReason    AS r
JOIN dbo.FactInternetSales          AS f
    ON  r.SalesOrderNumber     = f.SalesOrderNumber
    AND r.SalesOrderLineNumber = f.SalesOrderLineNumber
JOIN dbo.DimSalesReason             AS sr  ON r.SalesReasonKey = sr.SalesReasonKey
GROUP BY sr.SalesReasonReasonType, sr.SalesReasonName
ORDER BY NumeroOrdini DESC;

/*
FATTI
- Controllo: le righe dei sette motivi sommano 64.515. Dei 10 motivi presenti in
  DimSalesReason se ne usano solo 7.
- "Price" è di gran lunga il motivo più citato: 63,17% degli ordini. Seguono "On Promotion"
  (12,71%), "Manufacturer" (6,31%) e "Quality" (5,61%).
- Il fatturato collegato dipende dal tipo di prodotto: una riga "Price" vale in media 229,94,
  una riga "Manufacturer" 3.299,30.
- Le 1.551 righe "Quality" valgono esattamente 3.578,27 l'una (1.551 x 3.578,27 =
  5.549.896,77): è il prezzo della Road-150.
- Nel nome "Television  Advertisement" ci sono due spazi: piccolo difetto dell'anagrafica.

IPOTESI
- Un motivo legato a un solo modello è un artificio del dataset di esempio, non un
  comportamento reale dei clienti.
- "On Promotion" è citato nel 12,71% degli ordini, ma nel file 01 gli sconti sulle bici
  sono a zero: da chiarire nel file 04 con la tabella delle promozioni.

DECISIONE
- I motivi d'acquisto restano fuori dalla prima versione del modello: aggiungono una
  relazione molti-a-molti e raccontano poco. Li cito nel README come analisi esplorata.
*/


/* =====================================================================
   6. SINTESI DELLE SCOPERTE
   =====================================================================
   1. Tutti i 18.484 clienti in anagrafica hanno comprato. Il 62,86% ha fatto un solo ordine;
      il 37,14% con due o più ordini fa il 77,02% del fatturato.
   2. Il fatturato è concentrato su metà dei clienti: i primi 5 decili fanno il 98,05%.
      Non è un vero 80/20 (il primo 20% fa il 66,42%): è la separazione tra clienti con bici
      e clienti di soli accessori.
   3. Fino al 2012 quasi nessuno torna a comprare. Nel 2013 torna l'89,94% dei vecchi clienti
      e fa il 63,97% del fatturato: la crescita del 2013 è pari al fatturato dei ricorrenti.
   4. Professione e reddito non decidono chi compra una bici (quota tra il 44% e il 56% in
      tutti i gruppi), ma la spesa per cliente cresce con il reddito (1,8 volte tra la fascia
      più bassa e la più alta).
   5. Il motivo d'acquisto più citato è il prezzo (63,17% degli ordini).

   Decisioni per il modello
   - Vista clienti con geografia, professione, reddito e fascia di reddito.
   - Segmentazione principale: cliente con bici / cliente di soli accessori.
   - Clienti nuovi e ricorrenti calcolati con misure DAX.
   - Motivi d'acquisto fuori dalla prima versione del modello.

   Limiti del dataset (dati di esempio)
   - Riacquisto concentrato in un solo anno (2013) e su quasi tutti i vecchi clienti.
   - Il motivo "Quality" compare solo sulla Road-150.
   - "On Promotion" citato come motivo anche se gli sconti risultano a zero (da chiarire).
   ===================================================================== */
