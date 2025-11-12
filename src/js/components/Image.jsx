export default function Image(props) {
  return (
    <image {...props}>
      {props.children}
    </image>
  );
}
