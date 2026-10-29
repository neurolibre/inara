---
numbering:
  enumerator: S.%s
---

# Supplementary

```{figure} ./a.png
:label: figUnlabelledBefore
```

````markdown
:::{figure} ./shown-as-code.png
:label: notCounted
:::
````

:::{figure} ./b.png
:label: figSupp
Caption.
:::

:::{table} First
:label: tblSupp
| a |
|---|
| 1 |
:::

:::{list-table} Second
:label: tblList
* - a
:::
