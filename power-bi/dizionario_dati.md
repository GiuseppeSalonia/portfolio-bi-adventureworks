# Dizionario dei dati — Report Power BI "Vendite online AdventureWorks"

Descrive il modello del file `Report_Power_BI.pbix`: tabelle, relazioni, colonne visibili e le 27 misure DAX con definizione e formula.

- **Fonte**: database `AdventureWorksDW2025` su SQL Server, letto attraverso cinque viste (`05_viste.sql`).
- **Perimetro**: solo canale online. Il report mostra gli anni completi 2011-2013 (filtro `AnnoCompleto = 1` su tutte le pagine).
- **Origine del documento**: generato dalla tabella calcolata `INFO Riassunto` (funzioni DAX `INFO.VIEW`), nascosta nel report.

## Indice

1. [Tabelle](#tabelle)
2. [Relazioni](#relazioni)
3. [Colonne](#colonne)
4. [Misure](#misure)
5. [Formule DAX](#formule-dax)

## Tabelle

| Tabella | Ruolo | Vista SQL di origine | Contenuto |
|---|---|---|---|
| Vendite | Fatti | `vw_Vendite` | Una riga per riga d'ordine online (60.398 righe). |
| Calendario | Dimensione | `vw_Calendario` | Un giorno per riga, 2010-2014 (1.826 righe). Contrassegnata come tabella date. |
| Prodotti | Dimensione | `vw_Prodotti` | I 158 prodotti venduti online, con modello, sottocategoria e categoria. |
| Clienti | Dimensione | `vw_Clienti` | I 18.484 clienti online, senza dati personali (nome, email, indirizzo). |
| Territori | Dimensione | `vw_Territori` | I 10 territori di vendita su tre livelli: gruppo, paese, regione. |
| _Misure | Tabella delle misure | — | Contiene solo le misure DAX. |

## Relazioni

Modello a stella: quattro relazioni uno-a-molti, con filtro in una sola direzione (dalla dimensione ai fatti).

| Dimensione (lato 1) | Fatti (lato molti) | Chiave |
|---|---|---|
| Calendario | Vendite | `ChiaveData` |
| Clienti | Vendite | `ChiaveCliente` |
| Prodotti | Vendite | `ChiaveProdotto` |
| Territori | Vendite | `ChiaveTerritorio` |

## Colonne

Sono elencate le colonne visibili nel report. Sono **nascoste** e quindi non elencate: le quattro chiavi (`ChiaveData`, `ChiaveProdotto`, `ChiaveCliente`, `ChiaveTerritorio`), sia in `Vendite` sia nelle dimensioni, e le colonne `Quantita`, `Fatturato`, `Costo`, `Margine` di `Vendite`, che nei grafici si usano solo attraverso le misure.

### Calendario

| Colonna | Tipo | Descrizione |
|---|---|---|
| Data | Data | Giorno di calendario; colonna della tabella date contrassegnata. |
| Anno | Numero intero | Anno solare (2010-2014). |
| Trimestre | Numero intero | Trimestre dell'anno (1-4). |
| NumeroMese | Numero intero | Mese dell'anno (1-12); usato per ordinare la colonna Mese. |
| Mese | Testo | Nome del mese in italiano, ordinato per NumeroMese. |
| AnnoMese | Numero intero | Anno e mese nel formato AAAAMM (es. 201306). |
| AnnoCompleto | Numero intero | 1 per 2011, 2012 e 2013; 0 per gli anni incompleti 2010 e 2014. |

### Clienti

| Colonna | Tipo | Descrizione |
|---|---|---|
| Citta | Testo | Città del cliente. |
| StatoProvincia | Testo | Stato o provincia del cliente. |
| Professione | Testo | Professione dichiarata. |
| RedditoAnnuo | Decimale fisso | Reddito annuo dichiarato. |
| FasciaReddito | Testo | Quattro fasce di reddito, numerate per l'ordinamento. |
| TipoCliente | Testo | "Con bici" se il cliente ha comprato almeno una bici, altrimenti "Solo accessori". |
| DataPrimoOrdine | Data | Data del primo ordine online del cliente. |
| AnnoPrimoOrdine | Numero intero | Anno del primo ordine. |

### Prodotti

| Colonna | Tipo | Descrizione |
|---|---|---|
| Prodotto | Testo | Nome del prodotto; per bici e abbigliamento include colore e taglia. |
| Modello | Testo | Modello; livello usato per raggruppare i prodotti. |
| Sottocategoria | Testo | Sottocategoria (es. Road Bikes, Helmets). |
| Categoria | Testo | Bikes, Accessories o Clothing. |
| Colore | Testo | Colore del prodotto. |

### Territori

| Colonna | Tipo | Descrizione |
|---|---|---|
| Gruppo | Testo | Macro-area: Europe, North America, Pacific. |
| Paese | Testo | Paese del territorio di vendita. |
| Regione | Testo | Regione di vendita (per gli Stati Uniti: Northwest, Southwest...). |

### Vendite

| Colonna | Tipo | Descrizione |
|---|---|---|
| NumeroOrdine | Testo | Codice dell'ordine (es. SO43697); usato per contare gli ordini. |
| RigaOrdine | Numero intero | Posizione della riga dentro l'ordine. |

## Misure

Tutte le misure sono nella tabella `_Misure`. Il nome rimanda alla formula nella sezione successiva.

### Misure di base

| Misura | Descrizione |
|---|---|
| [Fatturato](#fatturato) | Importo delle vendite online, senza tasse e spedizione. |
| [Costo](#costo) | Costo standard dei prodotti venduti. |
| [Margine](#margine) | Margine lordo: fatturato meno costo standard. |
| [Margine %](#margine-) | Margine lordo diviso fatturato. |
| [Ordini](#ordini) | Numero di ordini distinti. |
| [Pezzi](#pezzi) | Pezzi venduti. |
| [Clienti](#clienti-1) | Clienti distinti con almeno un acquisto nel periodo. |
| [Valore medio ordine](#valore-medio-ordine) | Fatturato diviso numero di ordini. |
| [Fatturato per cliente](#fatturato-per-cliente) | Fatturato diviso clienti attivi. |

### Confronto con l'anno precedente

| Misura | Descrizione |
|---|---|
| [Fatturato AP](#fatturato-ap) | Fatturato dell'anno precedente. Vuoto se l'anno precedente è incompleto o se non è selezionato un solo anno. |
| [Var. fatturato %](#var-fatturato-) | Variazione % del fatturato rispetto all'anno precedente. |
| [Ordini AP](#ordini-ap) | Ordini dell'anno precedente, con le stesse regole di Fatturato AP. |
| [Var. ordini %](#var-ordini-) | Variazione % degli ordini rispetto all'anno precedente. |
| [Margine % AP](#margine--ap) | Margine % dell'anno precedente, con le stesse regole di Fatturato AP. |
| [Var. margine (pp)](#var-margine-pp) | Differenza del margine % rispetto all'anno precedente, in punti percentuali. |

### Quote sul totale

| Misura | Descrizione |
|---|---|
| [Quota fatturato % (prodotti)](#quota-fatturato--prodotti) | Quota del fatturato sul totale dei prodotti selezionati. |
| [Quota pezzi % (prodotti)](#quota-pezzi--prodotti) | Quota dei pezzi sul totale dei prodotti selezionati. |
| [Quota fatturato % (territori)](#quota-fatturato--territori) | Quota del fatturato sul totale dei territori selezionati. |
| [Quota clienti %](#quota-clienti-) | Quota dei clienti sul totale dei clienti selezionati. |
| [Quota fatturato % (clienti)](#quota-fatturato--clienti) | Quota del fatturato sul totale dei clienti selezionati. |

### Clienti nuovi e ricorrenti

| Misura | Descrizione |
|---|---|
| [Clienti nuovi](#clienti-nuovi) | Clienti il cui primo ordine cade nel periodo. |
| [Clienti ricorrenti](#clienti-ricorrenti) | Clienti attivi nel periodo che avevano già comprato prima. |
| [Quota clienti ricorrenti %](#quota-clienti-ricorrenti-) | Clienti ricorrenti diviso clienti attivi. |
| [Fatturato clienti nuovi](#fatturato-clienti-nuovi) | Fatturato del periodo generato dai clienti nuovi. |
| [Fatturato clienti ricorrenti](#fatturato-clienti-ricorrenti) | Fatturato del periodo generato dai clienti ricorrenti. |
| [Quota fatturato ricorrenti %](#quota-fatturato-ricorrenti-) | Quota del fatturato generata dai clienti ricorrenti. |
| [Quota clienti con bici %](#quota-clienti-con-bici-) | Quota dei clienti che hanno comprato almeno una bici. |

**Regole comuni**

- Le misure "AP" (anno precedente) restituiscono vuoto se non è selezionato un solo anno o se l'anno precedente è incompleto: così il 2011 non viene confrontato con i tre giorni del 2010.
- Le variazioni di una percentuale (margine) sono in punti percentuali, non in percentuale.
- `Ordini` e `Clienti` sono conteggi distinti: i totali non sono la somma delle righe.
- Nuovo e ricorrente dipendono dal periodo: i clienti ricorrenti di un anno non sono la somma di quelli dei mesi.

## Formule DAX

### Misure di base

#### Fatturato

```dax
Fatturato = SUM ( Vendite[Fatturato] )
// Fatturato: somma degli importi di vendita delle righe nel contesto
// (anno, paese, prodotto... quello che filtra il grafico)
```

#### Costo

```dax
Costo = SUM ( Vendite[Costo] )
// Costo standard dei prodotti venduti
```

#### Margine

```dax
Margine = SUM ( Vendite[Margine] )
// Margine lordo = Fatturato - Costo (già calcolato riga per riga nella vista)
```

#### Margine %

```dax
Margine % = DIVIDE ( [Margine], [Fatturato] )
// Rapporto tra margine e fatturato.
// DIVIDE invece di "/" restituisce vuoto, e non un errore, se il fatturato è zero.
```

#### Ordini

```dax
Ordini = DISTINCTCOUNT ( Vendite[NumeroOrdine] )
// Un ordine ha più righe, quindi si contano i numeri d'ordine distinti
```

#### Pezzi

```dax
Pezzi = SUM ( Vendite[Quantita] )
// Pezzi venduti
```

#### Clienti

```dax
Clienti = DISTINCTCOUNT ( Vendite[ChiaveCliente] )
// Clienti attivi: clienti distinti con almeno un acquisto nel contesto
```

#### Valore medio ordine

```dax
Valore medio ordine = DIVIDE ( [Fatturato], [Ordini] )
// Fatturato diviso numero di ordini
```

#### Fatturato per cliente

```dax
Fatturato per cliente = DIVIDE ( [Fatturato], [Clienti] )
// Spesa media per cliente attivo nel periodo: fatturato diviso clienti distinti.
```

### Confronto con l'anno precedente

#### Fatturato AP

```dax
Fatturato AP =
IF (
    HASONEVALUE ( Calendario[Anno] ),               -- calcola solo se è selezionato un unico anno
    CALCULATE (
        [Fatturato],                                -- la misura da ricalcolare...
        SAMEPERIODLASTYEAR ( Calendario[Data] ),    -- ...sulle stesse date, un anno prima
        Calendario[AnnoCompleto] = 1                -- ...ma solo se quell'anno è completo
    )
)
// AP = anno precedente. Restituisce vuoto per il 2011 (il 2010 è incompleto) e sul totale.
```

#### Var. fatturato %

```dax
Var. fatturato % =
VAR Attuale = [Fatturato]
VAR Precedente = [Fatturato AP]
RETURN
    DIVIDE ( Attuale - Precedente, Precedente )
// Variazione rispetto all'anno precedente. Vuoto se l'anno precedente non c'è.
```

#### Ordini AP

```dax
Ordini AP =
IF (
    HASONEVALUE ( Calendario[Anno] ),
    CALCULATE (
        [Ordini],
        SAMEPERIODLASTYEAR ( Calendario[Data] ),
        Calendario[AnnoCompleto] = 1
    )
)
// Ordini dell'anno precedente, con le stesse regole di Fatturato AP.
```

#### Var. ordini %

```dax
Var. ordini % =
VAR Attuale = [Ordini]
VAR Precedente = [Ordini AP]
RETURN
    DIVIDE ( Attuale - Precedente, Precedente )
// Variazione % del numero di ordini rispetto all'anno precedente.
```

#### Margine % AP

```dax
Margine % AP =
IF (
    HASONEVALUE ( Calendario[Anno] ),
    CALCULATE (
        [Margine %],
        SAMEPERIODLASTYEAR ( Calendario[Data] ),
        Calendario[AnnoCompleto] = 1
    )
)
// Margine % dell'anno precedente, con le stesse regole di Fatturato AP.
```

#### Var. margine (pp)

```dax
Var. margine (pp) =
VAR Attuale = [Margine %]
VAR Precedente = [Margine % AP]
RETURN
    IF ( NOT ISBLANK ( Precedente ), ( Attuale - Precedente ) * 100 )
// Differenza tra due percentuali, espressa in punti percentuali (pp).
```

### Quote sul totale

#### Quota fatturato % (prodotti)

```dax
Quota fatturato % (prodotti) =
DIVIDE (
    [Fatturato],                                        -- fatturato della riga (es. una categoria)
    CALCULATE ( [Fatturato], ALLSELECTED ( Prodotti ) ) -- fatturato di tutti i prodotti selezionati
)
// Quota di un prodotto, modello o categoria sul totale dei prodotti selezionati.
```

#### Quota pezzi % (prodotti)

```dax
Quota pezzi % (prodotti) =
DIVIDE (
    [Pezzi],
    CALCULATE ( [Pezzi], ALLSELECTED ( Prodotti ) )
)
// Come sopra, ma sui pezzi venduti.
```

#### Quota fatturato % (territori)

```dax
Quota fatturato % (territori) =
DIVIDE (
    [Fatturato],
    CALCULATE ( [Fatturato], ALLSELECTED ( Territori ) )
)
// Quota di un paese, gruppo o regione sul totale dei territori selezionati.
```

#### Quota clienti %

```dax
Quota clienti % =
DIVIDE (
    [Clienti],
    CALCULATE ( [Clienti], ALLSELECTED ( Clienti ) )
)
// Quota di un gruppo di clienti (tipo, fascia di reddito, professione) sui clienti selezionati.
```

#### Quota fatturato % (clienti)

```dax
Quota fatturato % (clienti) =
DIVIDE (
    [Fatturato],
    CALCULATE ( [Fatturato], ALLSELECTED ( Clienti ) )
)
// Quota di fatturato di un gruppo di clienti sul totale dei clienti selezionati.
```

### Clienti nuovi e ricorrenti

#### Clienti nuovi

```dax
Clienti nuovi =
VAR InizioPeriodo = MIN ( Calendario[Data] )    -- primo giorno del periodo nel contesto
VAR FinePeriodo = MAX ( Calendario[Data] )      -- ultimo giorno del periodo nel contesto
RETURN
    CALCULATE (
        [Clienti],                                  -- clienti attivi nel periodo...
        Clienti[DataPrimoOrdine] >= InizioPeriodo,  -- ...con il primo ordine
        Clienti[DataPrimoOrdine] <= FinePeriodo     --    dentro lo stesso periodo
    )
// Clienti attivi nel periodo il cui primo ordine cade nel periodo stesso.
```

#### Clienti ricorrenti

```dax
Clienti ricorrenti = [Clienti] - [Clienti nuovi]
// Clienti attivi nel periodo che avevano già comprato prima.
```

#### Quota clienti ricorrenti %

```dax
Quota clienti ricorrenti % = DIVIDE ( [Clienti ricorrenti], [Clienti] )
// Quota dei ricorrenti sui clienti attivi del periodo.
```

#### Fatturato clienti nuovi

```dax
Fatturato clienti nuovi =
VAR InizioPeriodo = MIN ( Calendario[Data] )
VAR FinePeriodo = MAX ( Calendario[Data] )
RETURN
    CALCULATE (
        [Fatturato],
        Clienti[DataPrimoOrdine] >= InizioPeriodo,
        Clienti[DataPrimoOrdine] <= FinePeriodo
    )
// Fatturato del periodo generato dai clienti nuovi (stessa logica di Clienti nuovi).
```

#### Fatturato clienti ricorrenti

```dax
Fatturato clienti ricorrenti = [Fatturato] - [Fatturato clienti nuovi]
// Fatturato del periodo generato dai clienti ricorrenti.
```

#### Quota fatturato ricorrenti %

```dax
Quota fatturato ricorrenti % = DIVIDE ( [Fatturato clienti ricorrenti], [Fatturato] )
// Quota del fatturato del periodo generata dai clienti ricorrenti.
```

#### Quota clienti con bici %

```dax
Quota clienti con bici % =
DIVIDE (
    CALCULATE (
        [Clienti],
        KEEPFILTERS ( Clienti[TipoCliente] = "Con bici" )   -- solo i clienti che hanno comprato bici
    ),
    [Clienti]                                               -- tutti i clienti del contesto
)
// Quota dei clienti del gruppo (fascia di reddito, paese...) che hanno comprato almeno una bici.
```
