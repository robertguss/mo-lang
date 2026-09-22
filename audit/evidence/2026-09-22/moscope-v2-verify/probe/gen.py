import json, random, sys

random.seed(int(sys.argv[1]))
n = int(sys.argv[2])
left = [0]


def leaf():
    return random.choice([None, True, False, random.randint(-10**6, 10**6), round(random.random() * 1e3, 3),
                          "".join(random.choice("abé—\U0001F600\"\\\n") for _ in range(random.randint(0, 6)))])


def val(d, width):
    left[0] -= 1
    if d <= 0 or left[0] <= 0 or random.random() < 0.2:
        return leaf()
    k = random.randint(0, width)
    if random.random() < 0.5:
        return [val(d - 1, width) for _ in range(k)]
    return {random.choice(["a", "b", "k%d" % random.randint(0, 30)]): val(d - 1, width) for _ in range(k)}


docs = []
for i in range(n):
    left[0] = 5000
    kind = i % 4
    if kind == 0:
        v = val(random.randint(2, 8), 40)  # wide
    elif kind == 1:  # deep chain
        v = 1
        for _ in range(random.randint(17, 500)):
            v = [v] if random.random() < .5 else {"a": v}
    elif kind == 2:  # many sibling containers
        v = [{"a": [], "b": {"c": [1, {"d": 2}]}} for _ in range(random.randint(16, 3000))]
    else:
        v = val(random.randint(3, 40), 5)  # mixed, deeper
    docs.append(json.dumps(v, ensure_ascii=bool(random.getrandbits(1))))
docs.append('{"a":1,"a":2,"b":{"a":3,"a":[4,5]}}')  # duplicate keys
docs.append("[" * 513 + "]" * 513)  # one past max depth
docs.append("[" * 512 + "]" * 512)  # at max depth
docs.append('{"a":[1,2,')  # truncated
print("\n".join(docs))
