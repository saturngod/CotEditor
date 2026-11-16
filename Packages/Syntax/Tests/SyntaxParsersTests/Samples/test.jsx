// JSX sample
import React, { useState } from "react";

const MAX_COUNT = 10;

function Counter({ label, initial = 0 }) {
  const [count, setCount] = useState(initial);

  /* increment handler */
  const increment = () => setCount((value) => Math.min(value + 1, MAX_COUNT));

  return (
    <div className="counter" data-count={count}>
      <Label text={label} />
      <button onClick={increment} disabled={count >= MAX_COUNT}>
        Clicked {count} times
      </button>
      <svg:rect width="10" height="10" />
    </div>
  );
}

export default Counter;
