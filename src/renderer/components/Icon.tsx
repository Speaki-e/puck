export type IconName = "folder" | "save" | "play" | "stop" | "sparkle" | "branch" | "gear";

export function Icon({ name }: { name: IconName }) {
  const paths = {
    folder: <><path d="M3 5.5h5l1.5 2H21v10.5a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V7.5a2 2 0 0 1 2-2Z" /><path d="M1.5 9h20" /></>,
    save: <><path d="M4 3h13l3 3v15H4z" /><path d="M8 3v6h8V3M8 21v-7h8v7" /></>,
    play: <path d="m8 5 11 7-11 7Z" />,
    stop: <rect x="6" y="6" width="12" height="12" rx="2" />,
    sparkle: <><path d="m12 2 1.3 4.2A6 6 0 0 0 17.8 11L22 12l-4.2 1.3a6 6 0 0 0-4.5 4.5L12 22l-1.3-4.2a6 6 0 0 0-4.5-4.5L2 12l4.2-1.3a6 6 0 0 0 4.5-4.5Z" /></>,
    branch: <><circle cx="6" cy="5" r="2" /><circle cx="18" cy="6" r="2" /><circle cx="6" cy="19" r="2" /><path d="M6 7v10M8 8c2 5 8 1 8-1" /></>,
    gear: <><circle cx="12" cy="12" r="3" /><path d="M12 3v2M12 19v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M3 12h2M19 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4" /></>,
  };

  return (
    <svg
      className="icon"
      viewBox="0 0 24 24"
      aria-hidden
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {paths[name]}
    </svg>
  );
}
