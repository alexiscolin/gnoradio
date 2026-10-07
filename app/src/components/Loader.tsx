/** Loader: three Bauhaus shapes hopping in turn (red circle, yellow square, blue triangle). */
export function Loader({ label = "Loading" }: { readonly label?: string }) {
  return <span className="dial-loading loader" role="status" aria-label={label}><i className="c" /><i className="s" /><i className="t" /></span>;
}
