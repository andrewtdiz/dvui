
import { cva } from "class-variance-authority";
import {cn} from "./cn";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-all duration-50 disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4 shrink-0 [&_svg]:shrink-0 outline-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px] aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive m-0",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground shadow-sm hover:bg-primary/90",
        destructive: "bg-destructive text-destructive-foreground shadow-xs hover:bg-destructive/90",
        outline: "border border-input bg-background shadow-xs hover:bg-accent hover:text-accent-foreground",
        secondary: "bg-secondary text-secondary-foreground shadow-xs hover:bg-secondary/80",
        ghost: "hover:bg-accent hover:text-accent-foreground border-none",
        menuitem: "hover:bg-accent/50 hover:text-accent-foreground border-none rounded-none! duration-0",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        default: "h-9 px-4 py-2 has-[>svg]:px-3",
        xs: "h-6 font-light text-xs rounded-md px-2 has-[>svg]:px-1.5",
        sm: "h-8 rounded-md px-3 has-[>svg]:px-2.5",
        lg: "h-10 rounded-md px-6 has-[>svg]:px-4",
        icon: "size-9",
        "icon-xs": "size-4 text-xs",
        "icon-sm": "size-6 text-sm",
        "icon-lg": "size-10",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

export default function Button(props) {
  const size = props.size || "default";
  const variant = props.variant || "default";
  const className = props.className || "";
  return (
    <button {...props} className={cn(className)}>
      {props.children}
    </button>
  );
}
