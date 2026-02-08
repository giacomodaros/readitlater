export default function LabelBadge({
  name,
  color,
  onRemove,
  onClick,
}: {
  name: string;
  color: string;
  onRemove?: () => void;
  onClick?: () => void;
}) {
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium"
      style={{ backgroundColor: color + "20", color }}
      onClick={onClick}
      role={onClick ? "button" : undefined}
    >
      {name}
      {onRemove && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            onRemove();
          }}
          className="ml-0.5 hover:opacity-70"
        >
          &times;
        </button>
      )}
    </span>
  );
}
