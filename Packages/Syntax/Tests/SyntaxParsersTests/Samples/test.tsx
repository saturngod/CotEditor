// TSX sample
import React, { useState } from "react";

const MAX_COUNT = 10;

interface CounterProps {
  label: string;
  initial?: number;
}

export function Counter({ label, initial = 0 }: CounterProps): JSX.Element {
  const [count, setCount] = useState<number>(initial);

  /* increment handler */
  const increment = (): void => setCount((value) => Math.min(value + 1, MAX_COUNT));
  const items = [1, 2, 3].map((item) => <li key={item}>{item}</li>);

  return (
    <div className="counter" data-count={count}>
      <Label text={label} />
      <button onClick={increment} disabled={count >= MAX_COUNT}>
        Clicked {count} times
      </button>
      <ul>{items}</ul>
    </div>
  );
}

export default Counter;
