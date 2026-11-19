#evaluate_equal_area.py
from pathlib import Path
from xml.etree import ElementTree as ET
import csv

import numpy as np
import xarray as xr

from shapely.geometry import Polygon
from shapely.ops import unary_union
from shapely import contains_xy

# ============================================================
# CONFIGURACIÓN
# ============================================================

CASES = ("x1", "x4", "x16", "x64", "x256")

OBSERVATIONS = [
    ("18:00", "2016-09-19T18:00:00",
     "TURRIALBA_ASH_201609191814.kml"),
    ("21:00", "2016-09-19T21:00:00",
     "TURRIALBA_ASH_201609192119.kml"),
]

RESOLUTION = 0.005

LON = np.arange(
    -85.0, -83.3 + RESOLUTION / 2, RESOLUTION
)
LAT = np.arange(
    9.3, 10.5 + RESOLUTION / 2, RESOLUTION
)

XX, YY = np.meshgrid(LON, LAT)

# Área aproximada de cada celda, en km².
CELL_AREA = (
    (111.32 * RESOLUTION) ** 2
    * np.cos(np.deg2rad(YY))
)

OUTPUT = Path("equal_area_metrics.csv")


# ============================================================
# LECTURA DE POLÍGONOS NOAA
# ============================================================

def read_polygons(filename):
    root = ET.parse(Path("NOAA") / filename).getroot()
    polygons = []

    for element in root.iter():
        if element.tag.split("}")[-1] != "Polygon":
            continue

        for ring in element.iter():
            if ring.tag.split("}")[-1] != "outerBoundaryIs":
                continue

            for child in ring.iter():
                if (
                    child.tag.split("}")[-1] == "coordinates"
                    and child.text
                ):
                    points = []

                    for item in child.text.strip().split():
                        lon, lat = map(
                            float, item.split(",")[:2]
                        )
                        points.append((lon, lat))

                    if len(points) >= 3:
                        polygon = Polygon(points)

                        if not polygon.is_valid:
                            polygon = polygon.buffer(0)

                        if not polygon.is_empty:
                            polygons.append(polygon)

    if not polygons:
        raise ValueError(
            f"No se encontraron polígonos en {filename}"
        )

    return unary_union(polygons)


# ============================================================
# LECTURA DE FALL3D
# ============================================================

def load_field(case, timestamp):
    path = Path(case) / "Turrialba.res.nc"

    if not path.is_file():
        raise FileNotFoundError(path)

    with xr.open_dataset(path) as ds:
        field = ds["tephra_col_mass"]

        # Selección de la salida más cercana a la hora
        # de validez NOAA, con tolerancia de 30 segundos.
        field = field.sel(
            time=np.datetime64(timestamp),
            method="nearest",
            tolerance=np.timedelta64(30, "s"),
        )
        # Interpolación espacial a la malla común.
        field = field.interp(
            lon=LON,
            lat=LAT
        )

        values = field.values.astype(float)

    return values


# ============================================================
# SELECCIÓN DE ÁREA EQUIVALENTE
# ============================================================

def select_equal_area(values, target_area):
    """
    Selecciona las celdas con mayor masa de ceniza
    hasta aproximarse al área NOAA.

    La selección no utiliza la ubicación del polígono NOAA.
    """

    valid = (
        np.isfinite(values)
        & (values > 0)
    )

    flat_values = values.ravel()
    flat_areas = CELL_AREA.ravel()

    valid_indices = np.flatnonzero(valid.ravel())

    if valid_indices.size == 0:
        return (
            np.zeros(values.shape, dtype=bool),
            np.nan,
        )

    # Orden descendente por concentración.
    order = np.argsort(
        -flat_values[valid_indices],
        kind="stable"
    )

    ranked_indices = valid_indices[order]
    ranked_areas = flat_areas[ranked_indices]

    cumulative_area = np.cumsum(ranked_areas)

    # Cantidad de celdas necesaria para alcanzar
    # aproximadamente el área observada.
    n = int(
        np.searchsorted(
            cumulative_area,
            target_area,
            side="left"
        )
    ) + 1

    n = min(n, ranked_indices.size)

    # Elegir entre n y n-1 según qué área se acerque más.
    if n > 1:
        area_with_n = cumulative_area[n - 1]
        area_without_last = cumulative_area[n - 2]

        if (
            abs(area_without_last - target_area)
            < abs(area_with_n - target_area)
        ):
            n -= 1

    selected = np.zeros(
        flat_values.size,
        dtype=bool
    )

    selected[ranked_indices[:n]] = True

    threshold = float(
        flat_values[ranked_indices[n - 1]]
    )

    return selected.reshape(values.shape), threshold


# ============================================================
# MÉTRICAS ESPACIALES
# ============================================================

def calculate_metrics(predicted, observed):
    intersection = float(
        np.sum(CELL_AREA[predicted & observed])
    )

    predicted_area = float(
        np.sum(CELL_AREA[predicted])
    )

    observed_area = float(
        np.sum(CELL_AREA[observed])
    )

    union = (
        predicted_area
        + observed_area
        - intersection
    )

    precision = (
        intersection / predicted_area
        if predicted_area > 0 else 0.0
    )

    recall = (
        intersection / observed_area
        if observed_area > 0 else 0.0
    )

    iou = (
        intersection / union
        if union > 0 else np.nan
    )

    dice = (
        2 * intersection
        / (predicted_area + observed_area)
        if predicted_area + observed_area > 0
        else np.nan
    )

    return {
        "iou": iou,
        "precision": precision,
        "recall": recall,
        "f1_dice": dice,
        "predicted_km2": predicted_area,
        "observed_km2": observed_area,
        "intersection_km2": intersection,
        "union_km2": union,
    }


# ============================================================
# EJECUCIÓN
# ============================================================

def main():
    print(
        "=== INICIO: EVALUACIÓN DE ÁREA EQUIVALENTE ==="
    )

    results = []

    for label, timestamp, filename in OBSERVATIONS:

        print(f"\n=== NOAA {label} UTC ===")

        polygon = read_polygons(filename)
        observed = contains_xy(polygon, XX, YY)

        target_area = float(
            np.sum(CELL_AREA[observed])
        )

        print(
            f"Área NOAA: {target_area:.3f} km²"
        )

        for case in CASES:
            values = load_field(case, timestamp)

            predicted, threshold = select_equal_area(
                values,
                target_area
            )

            metrics = calculate_metrics(
                predicted,
                observed
            )

            row = {
                "observation_utc": timestamp,
                "case": case,
                "equal_area_threshold_g_m2": threshold,
                "area_difference_km2": (
                    metrics["predicted_km2"]
                    - metrics["observed_km2"]
                ),
                **metrics,
            }

            results.append(row)

            print(
                f"{case:5} | "
                f"Umbral={threshold:.6g} | "
                f"IoU={metrics['iou']:.4f} | "
                f"Coincidencia={metrics['recall']:.2%} | "
                f"Área={metrics['predicted_km2']:.2f} km²"
            )

    with OUTPUT.open(
        "w", newline="", encoding="utf-8"
    ) as file:
        writer = csv.DictWriter(
            file,
            fieldnames=results[0].keys()
        )
        writer.writeheader()
        writer.writerows(results)

    print(
        f"\nResultados guardados: {OUTPUT}"
    )
    print(
        f"Total de evaluaciones: {len(results)}"
    )
    print(
        "=== FIN: EVALUACIÓN DE ÁREA EQUIVALENTE ==="
    )


if __name__ == "__main__":
    main()
