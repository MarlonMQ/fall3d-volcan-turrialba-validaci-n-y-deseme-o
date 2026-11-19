import numpy as np
import xarray as xr
import cfgrib

FECHAS = ["20160919", "20160920"]
SALIDA = "era5.turrialba.20160919-20160920.nc"

VARIABLES_REQUERIDAS = [
    "z", "q", "t", "u", "v", "w",
    "z_topo", "lsm", "blh", "zust", "swvl1",
    "tp", "u10", "v10", "t2m", "lnsp"
]


def procesar_dia(fecha):
    print(f"\n=== Procesando {fecha} ===")

    archivo_pl = f"era5.pl.{fecha}-{fecha}.nc"
    archivo_sfc = f"era5.sfc.{fecha}-{fecha}.grib"

    inicio = np.datetime64(
        f"{fecha[:4]}-{fecha[4:6]}-{fecha[6:8]}"
    )
    fin = inicio + np.timedelta64(1, "D")

    # Datos de niveles de presión
    pl = xr.open_dataset(archivo_pl)

    pl = pl.rename({
        "valid_time": "time",
        "pressure_level": "isobaricInhPa"
    })

    pl = pl[["z", "q", "t", "u", "v", "w"]]

    # Datos de superficie
    datasets = cfgrib.open_datasets(archivo_sfc)
    superficies = []

    for ds in datasets:
        if "step" in ds.dims and "time" in ds.dims:
            ds = ds.rename({"time": "start_time"})
            ds = ds.stack(time=("start_time", "step"))
            ds = ds.set_index(time="valid_time")
            ds = ds.sortby("time")

        elif "valid_time" in ds.coords:
            # Conservar las fechas validas y eliminar el tiempo
            # original antes de asignar el nombre "time".
            ds = ds.swap_dims({"time": "valid_time"})
            ds = ds.drop_vars("time", errors="ignore")
            ds = ds.rename({"valid_time": "time"})

        if "time" in ds.dims:
            ds = ds.where(
                (ds.time >= inicio) & (ds.time < fin),
                drop=True
            )

        if "z" in ds.data_vars:
            ds = ds.rename({"z": "z_topo"})

        # Eliminar coordenadas auxiliares que pueden
        # generar conflictos al unir los datasets.
        auxiliares = [
            "number", "expver", "surface",
            "depthBelowLandLayer", "heightAboveGround",
            "meanSea", "step", "start_time"
        ]

        ds = ds.drop_vars(auxiliares, errors="ignore")

        superficies.append(ds)

    sfc = xr.merge(
        superficies,
        compat="override",
        join="exact"
    )

    # Logaritmo de presión superficial
    if not np.all(np.isfinite(sfc["sp"].values)):
        raise ValueError("La presión superficial contiene valores no finitos")

    if np.any(sfc["sp"].values <= 0):
        raise ValueError("La presión superficial contiene valores no positivos")

    sfc["lnsp"] = np.log(sfc["sp"])
    sfc["lnsp"].attrs = {
        "long_name": "Logarithm of surface pressure",
        "units": "-"
    }

    # Conservar las variables requeridas
    sfc = sfc[
        [
            "z_topo", "lsm", "blh", "zust",
            "swvl1", "tp", "u10", "v10",
            "t2m", "lnsp"
        ]
    ]

    # Comprobar coincidencia temporal
    if not np.array_equal(pl.time.values, sfc.time.values):
        raise ValueError(
            f"Los tiempos de presión y superficie no coinciden: {fecha}"
        )

    ds_final = xr.merge(
        [pl, sfc],
        compat="override",
        join="exact"
    )

    if ds_final.sizes["time"] != 24:
        raise ValueError(f"El día {fecha} no contiene 24 horas")

    print("Horas:", ds_final.sizes["time"])
    print("Niveles:", ds_final.sizes["isobaricInhPa"])
    print("Variables:", len(ds_final.data_vars))

    return ds_final


dias = [procesar_dia(fecha) for fecha in FECHAS]

print("\n=== Uniendo ambos días ===")

final = xr.concat(
    dias,
    dim="time",
    data_vars="all",
    coords="minimal",
    compat="override"
)

final = final.sortby("time")

# Verificar las 48 horas consecutivas
tiempos = final.time.values

assert len(tiempos) == 48, "Se esperaban 48 registros"
assert len(np.unique(tiempos)) == 48, "Existen horas duplicadas"

diferencias = np.diff(tiempos)

assert np.all(
    diferencias == np.timedelta64(1, "h")
), "Los registros no son horarios consecutivos"

faltantes = [
    variable
    for variable in VARIABLES_REQUERIDAS
    if variable not in final.data_vars
]

if faltantes:
    raise ValueError(f"Variables faltantes: {faltantes}")

# Asegurar dimensiones de cada tipo de variable
for variable in ["z", "q", "t", "u", "v", "w"]:
    final[variable] = final[variable].transpose(
        "time", "isobaricInhPa", "latitude", "longitude"
    )

for variable in [
    "z_topo", "lsm", "blh", "zust", "swvl1",
    "tp", "u10", "v10", "t2m", "lnsp"
]:
    final[variable] = final[variable].transpose(
        "time", "latitude", "longitude"
    )

# Mantener una coordenada temporal CF compatible con FALL3D
final.time.encoding = {
    "units": "seconds since 1970-01-01 00:00:00",
    "calendar": "proleptic_gregorian",
    "dtype": "float64"
}

print("\n=== Guardando archivo ===")

final.to_netcdf(
    SALIDA,
    format="NETCDF4"
)

print("\n=== RESULTADO ===")
print("Archivo:", SALIDA)
print("Horas:", final.sizes["time"])
print("Primera:", final.time.values[0])
print("Última:", final.time.values[-1])
print("Niveles:", final.sizes["isobaricInhPa"])
print("Latitudes:", final.sizes["latitude"])
print("Longitudes:", final.sizes["longitude"])
print("Variables:", list(final.data_vars))
print("\nConversión completada correctamente.")
