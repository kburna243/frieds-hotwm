import type { ReactElement, SVGProps } from "react";

export type IconName =
  | "flame"
  | "burst"
  | "target"
  | "rumble"
  | "bolt"
  | "gamepad"
  | "heart"
  | "crown"
  | "bulb"
  | "bug"
  | "question"
  | "wrench"
  | "check"
  | "checkSquare"
  | "folder"
  | "bluetooth"
  | "star"
  | "starFilled"
  | "refresh"
  | "external"
  | "download"
  | "github"
  | "arrowRight"
  | "arrowDown"
  | "sparkle"
  | "code"
  | "cpu"
  | "vibrate";

type IconProps = SVGProps<SVGSVGElement> & {
  name: IconName;
  size?: number;
};

const S = 24;

/** Solid icons (filled paths) */
const FILLED: Partial<Record<IconName, ReactElement>> = {
  flame: (
    <path d="M13.5.7 12.9 3c3.2 1.3 5.3 4 5.3 7.5a1 1 0 0 1-1.9.4c-.4-.8-.9-1.4-1.6-1.9.2 2.6-1 4.4-2.6 5.3-1.7 1-2.7 2.3-2.7 4a5.6 5.6 0 0 0 11.2 0c0-1.2-.2-2.3-.6-3.4C22.9 18 20.4 23 14.6 23 8.5 23 4 18.6 4 13.2 4 7 9.4 3.3 13.5.7Z" />
  ),
  heart: (
    <path d="M12 21s-7.5-4.6-9.4-9C1.2 8.5 3.2 5 6.6 5c2 0 3.5 1.1 4.4 2.4.2.3.7.3.9 0C12.8 6.1 14.3 5 16.3 5c3.4 0 5.4 3.5 4 7-1.9 4.4-9.4 9-8.3 9Z" />
  ),
  starFilled: (
    <path d="m12 2.6 2.7 5.7 6.2.8-4.6 4.3 1.2 6.1L12 16.6 6.5 19.5l1.2-6.1L3.1 9.1l6.2-.8L12 2.6Z" />
  ),
  crown: (
    <path d="M3 7.5c.9 0 1.6.7 1.6 1.6 0 .3-.1.6-.2.8l2.6 1.6 3-4.4a1.6 1.6 0 1 1 3.2 0c0 .3-.1.6-.2.8l3 4.4 2.6-1.6c-.1-.2-.2-.5-.2-.8a1.6 1.6 0 1 1 2.2 1.5l-2 9.4c-.1.6-.6 1-1.2 1H5.2c-.6 0-1.1-.4-1.2-1l-2-9.4c-.5-.2-.9-.8-.9-1.4C1.1 8.2 2 7.5 3 7.5Z" />
  ),
  sparkle: (
    <path d="M12 1.5c.7 3.6 2.4 5.3 6 6-3.6.7-5.3 2.4-6 6-.7-3.6-2.4-5.3-6-6 3.6-.7 5.3-2.4 6-6ZM19.5 15c.4 1.8 1.2 2.6 3 3-1.8.4-2.6 1.2-3 3-.4-1.8-1.2-2.6-3-3 1.8-.4 2.6-1.2 3-3Z" />
  ),
};

/** Stroke icons (24x24, currentColor) */
const STROKE: Record<Exclude<IconName, keyof typeof FILLED>, ReactElement> = {
  burst: (
    <g>
      <path d="M12 2v4M12 18v4M2 12h4M18 12h4M5 5l2.8 2.8M16.2 16.2 19 19M19 5l-2.8 2.8M7.8 16.2 5 19" />
      <circle cx="12" cy="12" r="3.2" />
    </g>
  ),
  target: (
    <g>
      <circle cx="12" cy="12" r="8.5" />
      <circle cx="12" cy="12" r="4.5" />
      <circle cx="12" cy="12" r="1" />
      <path d="M12 1.5v3M12 19.5v3M1.5 12h3M19.5 12h3" />
    </g>
  ),
  rumble: (
    <g>
      <path d="M3 9h3l2-3h4l2 3h3a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-3l-2 3H8l-2-3H3a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1Z" />
      <path d="M6 12h.01M9 12h.01M12 12h.01M15 12h.01" />
    </g>
  ),
  vibrate: (
    <g>
      <rect x="8" y="4" width="8" height="16" rx="2" />
      <path d="M4 9v6M1.5 11v2M20 9v6M22.5 11v2" />
    </g>
  ),
  bolt: <path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z" />,
  gamepad: (
    <g>
      <path d="M7 8h10a5 5 0 0 1 5 5v1.5a3.5 3.5 0 0 1-6.3 2.1L14.6 15H9.4l-1.1 1.6A3.5 3.5 0 0 1 2 14.5V13a5 5 0 0 1 5-5Z" />
      <path d="M7.5 11.5v2M6.5 12.5h2M16 11.5h.01M18 13.5h.01" />
    </g>
  ),
  bulb: (
    <g>
      <path d="M9 18h6M10 21h4" />
      <path d="M12 3a6 6 0 0 0-3.5 10.9c.3.3.5.7.5 1.1v1h6v-1c0-.4.2-.8.5-1.1A6 6 0 0 0 12 3Z" />
    </g>
  ),
  bug: (
    <g>
      <rect x="8" y="7" width="8" height="12" rx="4" />
      <path d="M8 11H4M8 15H4M16 11h4M16 15h4M9 6 7.5 3.5M15 6l1.5-2.5M12 6V3" />
    </g>
  ),
  question: (
    <g>
      <circle cx="12" cy="12" r="9" />
      <path d="M9.5 9.5a2.5 2.5 0 1 1 3.6 2.2c-.7.4-1.1 1-1.1 1.8v.3" />
      <path d="M12 17.5h.01" />
    </g>
  ),
  wrench: (
    <path d="M14.5 6.5a4 4 0 0 1 5.4-3.7l-3 3 2.3 2.3 3-3A4 4 0 0 1 15.6 12L6.8 20.8a2.3 2.3 0 0 1-3.3-3.3L12.3 8.7c.5.1 1-.1 1.4-.4.5-.4.8-1 .8-1.8Z" />
  ),
  check: <path d="m4.5 12.5 5 5 10-11" />,
  checkSquare: (
    <g>
      <rect x="3" y="3" width="18" height="18" rx="3" />
      <path d="m8 12 2.8 2.8L16.5 9" />
    </g>
  ),
  folder: (
    <path d="M3 7.5A2.5 2.5 0 0 1 5.5 5h3l2 2.5h8A2.5 2.5 0 0 1 21 10v7a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17V7.5Z" />
  ),
  bluetooth: (
    <path d="M7 7l10 10-5 4V3l5 4L7 17" />
  ),
  star: (
    <path d="m12 3 2.7 5.6 6.1.8-4.5 4.2 1.2 6L12 16.7 6.5 19.6l1.2-6L3.2 9.4l6.1-.8L12 3Z" />
  ),
  refresh: (
    <g>
      <path d="M20.5 12a8.5 8.5 0 1 1-2.6-6.1" />
      <path d="M20.5 4v5h-5" />
    </g>
  ),
  external: (
    <g>
      <path d="M14 4h6v6" />
      <path d="M20 4 11 13" />
      <path d="M18 14v5a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h5" />
    </g>
  ),
  download: (
    <g>
      <path d="M12 3v12" />
      <path d="m7 11 5 5 5-5" />
      <path d="M4 20h16" />
    </g>
  ),
  github: (
    <path d="M9.2 22.5c-4.4 0-5.4-1.4-5.7-3.4-.3-2 .6-3.4.6-3.4-1.2-1.1-1.6-2.6-1.6-4.4 0-3.4 2.6-5.8 6.6-5.8.2 0 .4 0 .6-.1.4-1 1.4-2.4 3.3-2.4 1.6 0 2.4 1.1 2.4 2.3 0 .7-.3 1.4-.6 1.9 1.9.8 3.2 2.4 3.2 4.6 0 1.6-.4 2.8-1.3 3.7.2.6.4 1.6 0 2.7-.4 1.2-1.3 2.2-2.7 2.9-.6.3-1.7.5-3.1.5h-1.7Z" />
  ),
  arrowRight: (
    <g>
      <path d="M4 12h15" />
      <path d="m13 6 6 6-6 6" />
    </g>
  ),
  arrowDown: (
    <g>
      <path d="M12 4v15" />
      <path d="m6 13 6 6 6-6" />
    </g>
  ),
  code: (
    <g>
      <path d="m8 8-4 4 4 4M16 8l4 4-4 4M14 4l-4 16" />
    </g>
  ),
  cpu: (
    <g>
      <rect x="6" y="6" width="12" height="12" rx="2" />
      <rect x="10" y="10" width="4" height="4" />
      <path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3" />
    </g>
  ),
};

export function Icon({ name, size = 18, ...rest }: IconProps) {
  const filled = FILLED[name];
  return (
    <svg
      width={size}
      height={size}
      viewBox={`0 0 ${S} ${S}`}
      fill={filled ? "currentColor" : "none"}
      stroke={filled ? "none" : "currentColor"}
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      {...rest}
    >
      {filled ?? STROKE[name as Exclude<IconName, keyof typeof FILLED>]}
    </svg>
  );
}
