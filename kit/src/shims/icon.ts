/**
 * Stands in for Genbeya's client/app/ui/icon.ts in the kit's bundle: the
 * editor modules need only `iconElement`, and the rest of that module is an
 * Angular component. Draws the same shapes from icon-data.ts.
 */
import { ICONS, type IconName } from "genbeya/client/app/ui/icon-data";

const SVG = "http://www.w3.org/2000/svg";

export function iconElement(name: IconName, size = 16): SVGSVGElement {
  const svg = document.createElementNS(SVG, "svg");
  const attributes = { width: size, height: size, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": 2 };
  for (const [attribute, value] of Object.entries(attributes)) svg.setAttribute(attribute, String(value));
  svg.setAttribute("stroke-linecap", "round");
  svg.setAttribute("stroke-linejoin", "round");
  svg.setAttribute("aria-hidden", "true");
  svg.replaceChildren(
    ...ICONS[name].map(([tag, shape]) => {
      const element = document.createElementNS(SVG, tag);
      for (const [attribute, value] of Object.entries(shape)) element.setAttribute(attribute, value);
      return element;
    }),
  );
  return svg;
}
