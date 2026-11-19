#evaluate_fidelity.py
from pathlib import Path
from xml.etree import ElementTree as ET
import csv

import numpy as np
import xarray as xr

from shapely.geometry import Polygon
from shapely.ops import unary_union
from shapely import contains_xy

CASES = ("x1", "x4", "x16", "x64", "x256")

OBSERVATIONS = [
    ("18:00", "2016-09-19T18:00:00",
     "TURRIALBA_ASH_201609191814.kml"),
    ("21:00", "2016-09-19T21:00:00",
     "TURRIALBA_ASH_201609192119.kml"),
]

THRESHOLDS = [1e-8, 1e-6, 1e-4, 1e-2, 1e-1, 1.0]

# Dominio y resolución comunes para todas las mallas.
RESOLUTION = 0.005

LON = np.arange(-85.0, -83.3 + RESOLUTION / 2, RESOLUTION)
LAT = np.arange(9.3, 10.5 + RESOLUTION / 2, RESOLUTION)

XX, YY = np.meshgrid(LON, LAT)

# Aproximación del área de cada celda, en km².
CELL_AREA = (
    (111.32 * RESOLUTION) ** 2
    * np.cos(np.deg2rad(YY))
)

OUTPUT = Path("fidelity_metrics.csv")


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
                        parts = item.split(",")
                        points.append(
                            (float(parts[0]), float(parts[1]))
                        )

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

    union = predicted_area + observed_area - intersection

    iou = (
        intersection / union
        if union > 0 else np.nan
    )

    precision = (
        intersection / predicted_area
        if predicted_area > 0 else 0.0
    )

    recall = (
        intersection / observed_area
        if observed_area > 0 else 0.0
    )

    f1 = (
        2 * precision * recall / (precision + recall)
        if precision + recall > 0 else 0.0
    )

    return {
        "iou": iou,
        "precision": precision,
        "recall": recall,
        "f1_dice": f1,
        "predicted_km2": predicted_area,
        "observed_km2": observed_area,
        "intersection_km2": intersection,
        "union_km2": union,
    }


def load_field(case, timestamp):
    filepath = Path(case) / "Turrialba.res.nc"

    if not filepath.is_file():
        raise FileNotFoundError(
            f"No se encontró el resultado: {filepath}"
        )

    with xr.open_dataset(filepath) as ds:
        field = ds["tephra_col_mass"]

        # Selección de la salida más cercana a la hora
        # de validez NOAA, con tolerancia de 30 segundos.
        field = field.sel(
            time=np.datetime64(timestamp),
            method="nearest",
            tolerance=np.timedelta64(30, "s"),
        )

        # Interpolación espacial bilineal.
        field = field.interp(
            lon=LON,
            lat=LAT
        )

        values = field.values.astype(float)

    return values


def main():
    print("=== INICIO: EVALUACIÓN DE FIDELIDAD FALL3D ===")

    results = []

    for label, timestamp, filename in OBSERVATIONS:

        print(f"\n{'=' * 65}")
        print(f"OBSERVACIÓN NOAA: {label} UTC")
        print(f"{'=' * 65}")

        polygon = read_polygons(filename)
        observed = contains_xy(polygon, XX, YY)

        observed_area = float(
            np.sum(CELL_AREA[observed])
        )

        print(
            f"Área observada aproximada: "
            f"{observed_area:.3f} km²"
        )

        for case in CASES:
            print(f"\n=== MALLA {case.upper()} ===")

            values = load_field(case, timestamp)

            finite = np.isfinite(values)

            if np.any(finite):
                max_value = float(np.nanmax(values))
            else:
                max_value = np.nan

            print(
                f"Máximo de masa en columna: "
                f"{max_value:.6g} g/m²"
            )

            for threshold in THRESHOLDS:
                predicted = (
                    finite & (values >= threshold)
                )

                metrics = calculate_metrics(
                    predicted, observed
                )

                row = {
                    "observation_utc": timestamp,
                    "case": case,
                    "threshold_g_m2": threshold,
                    "max_col_mass_g_m2": max_value,
                    **metrics,
                }

                results.append(row)

                print(
                    f"T={threshold:.0e} | "
                    f"IoU={metrics['iou']:.4f} | "
                    f"P={metrics['precision']:.4f} | "
                    f"R={metrics['recall']:.4f} | "
                    f"F1={metrics['f1_dice']:.4f}"
                )

    if results:
        with OUTPUT.open(
            "w", newline="", encoding="utf-8"
        ) as file:
            writer = csv.DictWriter(
                file,
                fieldnames=results[0].keys()
            )

            writer.writeheader()
            writer.writerows(results)

    print(f"\n=== RESULTADOS GUARDADOS: {OUTPUT} ===")
    print(f"Evaluaciones realizadas: {len(results)}")
    print("=== FIN: EVALUACIÓN DE FIDELIDAD ===")


if __name__ == "__main__":
    main()
