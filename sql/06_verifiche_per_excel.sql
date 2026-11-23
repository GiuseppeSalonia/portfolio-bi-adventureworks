/* =====================================================================
   PORTFOLIO BI - ADVENTUREWORKS
   File 06 - Verifiche a supporto del file Excel (fase 4 del progetto)
   ---------------------------------------------------------------------
   Database : AdventureWorksDW2025 su SQL Server 2025
   Canale   : Internet (viste dbo.vw_Vendite, dbo.vw_Calendario, dbo.vw_Prodotti)
   Scopo    : rispondere con una query alle domande che nascono costruendo il file
              Controllo_Gestione_AdventureWorks.xlsx, quando il dato non si può leggere
              dalla tabella mensile tblConsuntivo (per esempio una data esatta).

   Contenuto
     1. Data di lancio delle linee di prodotto

   Definizioni
     Linea = sottocategoria per le bici (Road Bikes, Mountain Bikes, Touring Bikes),
             categoria per Accessories e Clothing. È la stessa regola della colonna
             Linea creata in Power Query.

   I numeri citati nei commenti sono i risultati delle query di questo file
   (esecuzione del 16 novembre 2026).
   ===================================================================== */

USE AdventureWorksDW2025;
GO


-- =====================================================================
-- 1. DATA DI LANCIO DELLE LINEE DI PRODOTTO
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1.1 In che giorno parte ogni linea, e quanti giorni di vendita ha entro la fine del 2012?
--     Serve al budget 2013: per le linee senza un anno intero di storico i pezzi a budget
--     si calcolano dal ritmo giornaliero dei primi giorni (foglio Ipotesi, ipotesi 2).
-- ---------------------------------------------------------------------

-- Passo 1: ogni vendita con la sua linea (stessa regola della colonna Linea in Excel)
WITH VenditeConLinea AS (
    SELECT
        CASE WHEN p.Categoria = 'Bikes'
             THEN p.Sottocategoria
             ELSE p.Categoria END                       AS Linea,
        c.Data,
        c.Anno,
        v.Quantita
    FROM dbo.vw_Vendite         AS v
    JOIN dbo.vw_Calendario      AS c   ON v.ChiaveData     = c.ChiaveData
    JOIN dbo.vw_Prodotti        AS p   ON v.ChiaveProdotto = p.ChiaveProdotto
)

-- Passo 2: per ogni linea, primo giorno di vendita, giorni di vendita fino a fine 2012
--          (estremi compresi, per questo "+ 1") e pezzi venduti nel 2012
SELECT
    Linea,
    MIN(Data)                                           AS PrimaVendita,
    DATEDIFF(DAY, MIN(Data), '2012-12-31') + 1          AS GiorniFinoAFine2012,
    SUM(CASE WHEN Anno = 2012
             THEN Quantita ELSE 0 END)                  AS Pezzi2012
FROM VenditeConLinea
GROUP BY Linea
ORDER BY PrimaVendita;

/*
RISULTATO
    Linea             PrimaVendita   GiorniFinoAFine2012   Pezzi2012
    Road Bikes        2010-12-29     734                   2.158
    Mountain Bikes    2010-12-29     734                   1.098
    Clothing          2012-12-28     4                     22
    Touring Bikes     2012-12-28     4                     13
    Accessories       2012-12-28     4                     106

FATTI
- Road Bikes e Mountain Bikes si vendono dal primo giorno dei dati (29 dicembre 2010).
- Touring Bikes, Accessories e Clothing partono tutte lo stesso giorno, il 28 dicembre 2012:
  nel 2012 hanno 4 giorni di vendita (28, 29, 30 e 31 dicembre).
- Controllo: i pezzi del 2012 sommano 3.397 (2.158 + 1.098 + 22 + 13 + 106), come nel
  file 01 (query 2.1) e nel foglio Controlli del file Excel.
- Per Accessories e Clothing la data conferma il file 01 (query 3.2). Per le Touring è un
  dato nuovo: nel file 01 risultavano solo "13 pezzi nel 2012", senza la data.

IPOTESI
- Tre linee lanciate lo stesso giorno a fine dicembre confermano l'ipotesi del file 01:
  il catalogo sembra cambiare ogni anno a fine dicembre. È una caratteristica del dataset
  di esempio.

DECISIONE
- Nel foglio Ipotesi il parametro "Giorni di vendita linee nuove nell'anno base" vale 4
  (cella p_GiorniLancio) per tutte e tre le linee nuove.
- Pezzi a budget 2013 delle linee nuove = pezzi 2012 / 4 * 365:
  Touring Bikes 1.186, Accessories 9.673, Clothing 2.008.

LIMITE
- Quattro giorni a cavallo di fine anno sono una base debole per stimare un anno intero:
  va dichiarato nel foglio Ipotesi e nel README.
*/
