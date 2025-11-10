export default function Label(props) {
  return (
    <label {...props}>
      {props.children}
    </label>
  );
}
