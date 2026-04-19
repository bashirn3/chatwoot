#!/usr/bin/env node
/**
 * One-shot generator for the country paths used by the onboarding
 * CountryPicker.vue map. Consumes a WGS84 GeoJSON of European countries,
 * projects the coordinates onto an SVG viewBox (Mercator), and writes a
 * JS module that exports:
 *   - EU_MAP_VIEWBOX   — full-canvas viewBox string
 *   - COUNTRY_PATHS    — { ISO2: 'M…Z' } per country
 *   - COUNTRY_BBOXES   — { ISO2: { x, y, w, h } } per country in viewBox coords
 *
 * Run from repo root:
 *   node scripts/generate_europe_paths.mjs <path-to-europe.geojson>
 */

import fs from 'node:fs';
import path from 'node:path';

// Mercator viewport covering the European theatre wide enough to include
// the European part of Russia, Ukraine, Belarus, Moldova, the Balkans,
// Greece and Turkey. The CountryPicker renders this data inside its own
// smaller viewBox centred on the Nordics + UK by default; the extra
// geography ensures no country floats in an empty void.
const VIEW_W = 1500;
const LON_MIN = -20;
const LON_MAX = 50;
const LAT_MIN = 34;
const LAT_MAX = 72;

const mercY = deg => Math.log(Math.tan(Math.PI / 4 + (deg * Math.PI) / 360));
const MERC_Y_MIN = mercY(LAT_MIN);
const MERC_Y_MAX = mercY(LAT_MAX);
const PIXELS_PER_LNG = VIEW_W / (LON_MAX - LON_MIN);
const VIEW_H = Math.round(
  (MERC_Y_MAX - MERC_Y_MIN) * (180 / Math.PI) * PIXELS_PER_LNG
);

// ACTIVE = regions we serve. EXPANSION = coming-soon tiles. CONTEXT = shown
// non-clickable so the continent reads as a continent, not a floating set
// of active blobs.
const ACTIVE = ['DE', 'FR', 'IT', 'FI', 'SE', 'NO', 'GB'];
const EXPANSION = ['NL', 'IE', 'ES', 'BE', 'CH', 'AT', 'DK', 'PL'];
const CONTEXT = [
  'PT', 'CZ', 'SK', 'HU', 'SI', 'HR', 'RO', 'BG', 'GR', 'AL',
  'MK', 'ME', 'RS', 'BA', 'LU', 'LI', 'EE', 'LV', 'LT',
  'IS', 'FO', 'AD', 'MC', 'SM', 'VA', 'MT', 'CY',
  // Eastern EU + Russia + Turkey for complete context. Russia is clipped
  // at LON_MAX=50 so only the European half renders.
  'UA', 'BY', 'MD', 'RU', 'TR', 'GE', 'AM', 'AZ'
];
const KEEP = new Set([...ACTIVE, ...EXPANSION, ...CONTEXT]);

const project = ([lon, lat]) => {
  const x = ((lon - LON_MIN) / (LON_MAX - LON_MIN)) * VIEW_W;
  const my = mercY(Math.max(-85, Math.min(85, lat)));
  const y = VIEW_H - ((my - MERC_Y_MIN) / (MERC_Y_MAX - MERC_Y_MIN)) * VIEW_H;
  return [x, y];
};

const rdp = (points, epsilon) => {
  if (points.length <= 2) return points;
  let maxDist = 0;
  let idx = 0;
  const [start, end] = [points[0], points[points.length - 1]];
  for (let i = 1; i < points.length - 1; i += 1) {
    const d = perpendicularDistance(points[i], start, end);
    if (d > maxDist) {
      maxDist = d;
      idx = i;
    }
  }
  if (maxDist > epsilon) {
    const left = rdp(points.slice(0, idx + 1), epsilon);
    const right = rdp(points.slice(idx), epsilon);
    return [...left.slice(0, -1), ...right];
  }
  return [start, end];
};

const perpendicularDistance = ([px, py], [ax, ay], [bx, by]) => {
  const dx = bx - ax;
  const dy = by - ay;
  if (dx === 0 && dy === 0) return Math.hypot(px - ax, py - ay);
  const t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
  const cx = ax + t * dx;
  const cy = ay + t * dy;
  return Math.hypot(px - cx, py - cy);
};

// Build both the path `d` and the bounding box for a geometry in one pass.
const geometryToPathAndBBox = geometry => {
  const pieces = [];
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;

  const polygons =
    geometry.type === 'MultiPolygon'
      ? geometry.coordinates
      : [geometry.coordinates];

  for (const polygon of polygons) {
    const outer = polygon[0];
    if (!outer || outer.length < 4) continue;
    const projected = outer.map(project);
    const simplified = rdp(projected, 0.6);
    if (simplified.length < 3) continue;
    for (const [x, y] of simplified) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
    const [first, ...rest] = simplified;
    const body = rest
      .map(([x, y]) => `L${x.toFixed(1)} ${y.toFixed(1)}`)
      .join('');
    pieces.push(`M${first[0].toFixed(1)} ${first[1].toFixed(1)}${body}Z`);
  }

  if (pieces.length === 0) return null;
  return {
    path: pieces.join(' '),
    bbox: {
      x: +minX.toFixed(1),
      y: +minY.toFixed(1),
      w: +(maxX - minX).toFixed(1),
      h: +(maxY - minY).toFixed(1),
    },
  };
};

const main = () => {
  const input = process.argv[2];
  if (!input) {
    console.error('Usage: node scripts/generate_europe_paths.mjs <europe.geojson>');
    process.exit(1);
  }
  const raw = fs.readFileSync(input, 'utf8');
  const geo = JSON.parse(raw);
  const paths = {};
  const bboxes = {};
  for (const feature of geo.features) {
    const iso =
      feature.properties?.ISO2 ||
      feature.properties?.iso_a2 ||
      feature.properties?.iso;
    if (!iso || !KEEP.has(iso)) continue;
    const result = geometryToPathAndBBox(feature.geometry);
    if (result) {
      paths[iso] = result.path;
      bboxes[iso] = result.bbox;
    }
  }
  const outPath = path.resolve(
    'app/javascript/dashboard/routes/dashboard/onboarding/countryPaths.js'
  );
  const header = `// AUTO-GENERATED by scripts/generate_europe_paths.mjs — do not hand-edit.
// Source: europe.geojson (WGS84) simplified to viewBox ${VIEW_W}×${VIEW_H}.
// Lat/lng bounds: ${LAT_MIN}..${LAT_MAX}°N, ${LON_MIN}..${LON_MAX}°E.

export const EU_MAP_VIEWBOX = '0 0 ${VIEW_W} ${VIEW_H}';

export const COUNTRY_PATHS = Object.freeze(${JSON.stringify(paths, null, 2)});

export const COUNTRY_BBOXES = Object.freeze(${JSON.stringify(bboxes, null, 2)});
`;
  fs.writeFileSync(outPath, header);
  const size = Buffer.byteLength(header, 'utf8');
  console.log(
    `Wrote ${Object.keys(paths).length} countries (${(size / 1024).toFixed(1)} KB) → ${outPath}`
  );
};

main();
