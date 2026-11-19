# Reproducibilidad: FALL3D, volcán Turrialba (19 de septiembre de 2016)

Este repositorio reúne las configuraciones y los scripts empleados en un estudio de dispersión de ceniza con FALL3D y su evaluación frente a polígonos del Washington VAAC. Incluye el piloto de sensibilidad vertical, cinco discretizaciones horizontales y una matriz de **5 mallas × 6 cantidades de procesos MPI = 30 simulaciones**.

> **Alcance.** Los scripts permiten preparar y enviar los experimentos en un clúster compatible con Slurm y con FALL3D compilado. **No** incluyen el ejecutable de FALL3D, los datos ERA5 brutos, los grandes NetCDF resultantes ni la configuración de credenciales de la API. La descarga de ERA5 mediante las herramientas incluidas en FALL3D debe realizarse previamente. Por tanto, la reproducción completa requiere obtener esas dependencias externas.

## Organización

- `config/Turrialba_x{1,4,16,64,256}.inp`: configuraciones de las cinco mallas (con `NZ=40`).
- `slurm/preparar_entradas.sh`: configura directorios de trabajo y programa `SetTgsd`, `SetSrc`, `SetDbs` para las cinco mallas.
- `slurm/preparacion_automatica.slurm`: ejecuta las etapas preparativas en Slurm.
- `slurm/enviar_cola.sh`: envía **30** solvers MPI, en secuencia y con dependencias `afterok`.
- `slurm/solver_automatico.slurm`: ejecuta FALL3D y archiva NetCDF, log y tiempo del solver.
- `slurm/lanzar_todo.sh`: encadena **10 trabajos preparativos + 30 solvers** en una sola invocación.
- `slurm/verificar_particion.sh`: comprueba previamente si `kura` admite la duración requerida para x256.
- `slurm/x*/`: scripts históricos por malla, conservados como evidencia del procedimiento original; no son necesarios para el nuevo lanzador.
- `meteorologia/convertir_era5_turrialba.py`: conversión de las entradas ERA5 obtenidas para el estudio.
- `piloto-vertical/nz{20,40,60}/`: entradas y scripts de los experimentos piloto.
- `analisis-espacial/evaluate_fidelity.py`: concordancia de masa en columna frente a los KML, usando umbrales fijos.
- `analisis-espacial/evaluate_equal_area.py`: selección de regiones de área aproximadamente equivalente a la observación.
- `analisis-espacial/NOAA/`: observaciones KML. Los scripts de métricas utilizan los archivos de las emisiones `201609191814` y `201609192119`.
- `resultados/`: CSV originales de referencia (tiempos, métricas espaciales y manifiesto histórico).

## 1. Requisitos de cómputo

Los scripts de Slurm se basan en el entorno utilizado en Kabré:

- FALL3D: compilación local del código utilizado en el proyecto (versión identificada en el estudio: `v9.1.0-40-gf021a63`).
- GNU GCC 9.3.0; OpenMPI 4.0.5; bibliotecas HDF5/NetCDF compatibles con el ejecutable.
- Slurm, `sbatch`, `squeue`, `scontrol`, `mpirun` y Bash.
- Partición `kura`, cuenta `ucr`, un nodo por simulación. **Estos valores están fijados en los scripts de ejemplo** y deben adaptarse si el sitio de ejecución cambia.

Los scripts conservan las rutas `/opt/...` del entorno original para reproducir la configuración utilizada. En un clúster distinto, adaptar `PATH` y `LD_LIBRARY_PATH` en `slurm/preparacion_automatica.slurm` y `slurm/solver_automatico.slurm`, y verificar que el ejecutable FALL3D fue enlazado con bibliotecas compatibles.

El número de procesos MPI **no es** el número de nodos: todas las simulaciones solicitan un solo nodo y usan entre 1 y 32 procesos MPI.

## 2. Datos meteorológicos ERA5

La descarga original se realizó mediante la interfaz/API de ERA5 incorporada en el ecosistema de herramientas de FALL3D. Las solicitudes originales de descarga no están incluidas en este repositorio, por lo que **no puede inferirse de los archivos presentes la invocación exacta**. Se deben recuperar las mismas solicitudes ERA5 (fechas, variables, niveles y dominio) antes de afirmar reproducción íntegra de la entrada meteorológica.

El script de conversión `meteorologia/convertir_era5_turrialba.py` espera en su directorio de ejecución:

```text
era5.pl.20160919-20160919.nc
era5.pl.20160920-20160920.nc
era5.sfc.20160919-20160919.grib
era5.sfc.20160920-20160920.grib
```

Después de obtener estos cuatro archivos, desde la carpeta que los contiene:

```bash
python /ruta/al/repositorio/meteorologia/convertir_era5_turrialba.py
```

Esto debe generar `era5.turrialba.20160919-20160920.nc`, con 48 registros horarios consecutivos. El nuevo lanzador recibe la **ruta absoluta** de este archivo mediante `METEO_FILE` y crea enlaces `Turrialba.era5.nc` en los cinco directorios de trabajo. No almacene credenciales de Copernicus en Git.

Para instalar las dependencias Python del procesado y análisis (en un entorno virtual):

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

La instalación de las bibliotecas del entorno de ejecución HPC (MPI, NetCDF, etc.) es independiente de `requirements.txt`.

## 3. Preparación y envío de los 30 experimentos

> **Atención:** el envío real consume recursos HPC. Ejecutar primero `DRY_RUN=1` y comprobar el límite de tiempo permitido por `kura` (`scontrol show partition kura`). El script solicita hasta **72 horas** para cada combinación x256, incluida MPI1; si la partición no lo admite, el sitio de ejecución debe ajustarse antes del envío. El modo de prueba no envía trabajos ni modifica resultados.

En Kabré, situarse en el repositorio clonado y establecer:

```bash
export WORK_ROOT="/work/$USER/fall3d/reproduccion-nz40"
export FALL3D_BIN="$HOME/cc_investigation/fall3d/build-openmpi-correcto/bin/Fall3d.x"
export METEO_FILE="/ruta/absoluta/era5.turrialba.20160919-20160920.nc"
```

Probar las etapas sin consumir recursos:

```bash
DRY_RUN=1 bash slurm/lanzar_todo.sh
```

El modo de prueba debe mostrar **10 trabajos preparativos** y **30 simulaciones**. Tras comprobar partición, ejecutable, meteorología y disponibilidad de recursos, ejecutar:

```bash
bash slurm/lanzar_todo.sh
```

El lanzador hace lo siguiente:

1. Copia las cinco configuraciones `config/Turrialba_x*.inp` a `WORK_ROOT/x*/Turrialba.inp`.
2. Enlaza el NetCDF meteorológico común como `WORK_ROOT/x*/Turrialba.era5.nc`.
3. Programa en Slurm, por cada malla, `SetTgsd` y `SetSrc` (etapa `source`) seguidos de `SetDbs` (etapa `dbs`). El orden es secuencial para evitar interferencias y simplificar el registro de procedencia.
4. Programa las 30 simulaciones de FALL3D, todas dependientes de la preparación y encadenadas mediante `afterok`.
5. Guarda resultados en `WORK_ROOT/x*/resultados/mpiN/`.

**No ejecuta la descarga de ERA5 ni la conversión meteorológica**. Esas etapas deben estar completas antes del envío.

Si las cinco mallas ya fueron preparadas en `WORK_ROOT` (todos los archivos de entrada presentes), se puede enviar solamente la matriz MPI:

```bash
DRY_RUN=1 bash slurm/enviar_cola.sh
bash slurm/enviar_cola.sh
```

`WORK_ROOT` debe contener un espacio de trabajo **nuevo** para el flujo completo. El lanzador aborta si encuentra manifiestos existentes o salidas de etapas anteriores, para evitar mezclas accidentales. En caso de fallo parcial, consultar y resolver los trabajos anteriores antes de reutilizar o limpiar el directorio; **no** ejecutar nuevamente el lanzador sobre un experimento parcial.

### Configuración de la matriz

| Malla | NX | NY | NZ |
|---|---:|---:|---:|
| x1 | 66 | 50 | 40 |
| x4 | 132 | 100 | 40 |
| x16 | 264 | 200 | 40 |
| x64 | 528 | 400 | 40 |
| x256 | 1056 | 800 | 40 |

| Procesos MPI | PX | PY | PZ |
|---|---:|---:|---:|
| 1 | 1 | 1 | 1 |
| 2 | 2 | 1 | 1 |
| 4 | 2 | 2 | 1 |
| 8 | 4 | 2 | 1 |
| 16 | 4 | 4 | 1 |
| 32 | 8 | 4 | 1 |

El resto de los parámetros físicos del modelo proviene de los archivos `.inp`. El tipo de salida relevante para las comparaciones VAAC es `tephra_col_mass` (masa por columna atmosférica), **no depósito superficial**.

### Seguimiento de trabajos y registro de tiempos

Los manifiestos quedan en:

```text
$WORK_ROOT/trabajos_preparacion.tsv
$WORK_ROOT/trabajos_escalabilidad.tsv
```

Ejemplo de consulta de los trabajos enviados:

```bash
squeue -u "$USER"
sacct -j ID_DEL_TRABAJO --format=JobID,JobName,Partition,State,Elapsed,AllocCPUS,NNodes,NodeList
```

El archivo `metricas.txt` de cada simulación recoge los segundos alrededor de `mpirun` medidos por el script; `sacct Elapsed` mide la duración registrada por Slurm y no debe confundirse con el tiempo exclusivo del solver. **Utilizar el mismo tipo de tiempo al calcular las aceleraciones**: `S_p = T_1 / T_p`; eficiencia `E_p = S_p / p`.

**Diferencia respecto al registro histórico:** el envío original automatizó 29 trabajos porque x1/MPI32 ya estaba completado. Además, el tiempo histórico de x256/MPI1 provino de un trabajo completado en la partición `kura-long`, nodo `kura-1a.cnca`. El nuevo flujo solicita toda la matriz en `kura`, pero **no debe atribuirse el resultado histórico de x256/MPI1 a esa nueva solicitud**. Para una réplica, comparar los nuevos resultados y sus condiciones de ejecución con los CSV originales.

## 4. Análisis espacial

Los dos scripts trabajan sobre los archivos:

```text
analisis-espacial/x1/Turrialba.res.nc
analisis-espacial/x4/Turrialba.res.nc
analisis-espacial/x16/Turrialba.res.nc
analisis-espacial/x64/Turrialba.res.nc
analisis-espacial/x256/Turrialba.res.nc
```

En Linux, pueden enlazarse (sin copiar los NetCDF) los resultados de MPI32 al esquema esperado:

```bash
for MESH in x1 x4 x16 x64 x256; do
    mkdir -p "analisis-espacial/$MESH"
    ln -s "$WORK_ROOT/$MESH/resultados/mpi32/Turrialba.res.nc" \
        "analisis-espacial/$MESH/Turrialba.res.nc"
done
```

A continuación:

```bash
cd analisis-espacial
python evaluate_fidelity.py
python evaluate_equal_area.py
```

Ambos programas esperan los KML en `analisis-espacial/NOAA/`, trabajan en una malla común de `0.005°` y producen `fidelity_metrics.csv` y `equal_area_metrics.csv` en el directorio actual. Los resultados de referencia ya incluidos se encuentran en `resultados/`.

**Precaución metodológica:** los lectores KML de estos scripts toman todos los elementos `Polygon` presentes. Antes de afirmar que se usó exclusivamente la carpeta `Observed Ash`, conviene verificar que los KML relevantes no incluyan polígonos adicionales de otras categorías. La interpolación a una malla común no aumenta la información física disponible en las mallas más gruesas.

## 5. Piloto vertical

Las configuraciones y scripts de `piloto-vertical/nz20`, `nz40` y `nz60` se conservan para documentar la decisión de trabajar con 40 celdas verticales. **No son parte de las 30 simulaciones de escalabilidad horizontal** y no están programados por `slurm/lanzar_todo.sh`. Para repetirlos, revisar sus rutas y recursos específicos antes de ejecutarlos.

## 6. Límites de reproducibilidad

- En un clúster compartido no está garantizada la misma asignación de nodo, afinidad de CPU, contención ni el mismo tiempo de pared.
- Las mediciones históricas de `kura` y `kura-long` deben identificar correctamente su procedencia; dos nodos pueden tener especificaciones nominales iguales sin asegurar rendimiento idéntico.
- El repositorio no distribuye los grandes datos meteorológicos ni las salidas NetCDF. Se deben recuperar o regenerar a partir de las fuentes originales.
- Los scripts de preparación no automatizan la solicitud ERA5; faltan los parámetros exactos de aquella solicitud para declarar reproducibilidad completa de la adquisición meteorológica.
- Los scripts originales incluyen rutas y bibliotecas particulares de Kabré. En otras infraestructuras hace falta adaptar el entorno y validar el ejecutable.
- Para comparar con los CSV históricos es necesario identificar qué valores son tiempos `sacct Elapsed` y cuáles corresponden al temporizador interno del script.

