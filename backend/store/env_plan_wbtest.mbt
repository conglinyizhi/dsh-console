// env_plan 的合并规则（§106）：把纯函数 plan_env_map 单独钉住。
// 这四条以前是手测的，改一行就可能回归。

///|
fn map1(k : String, v : String) -> Map[String, String] {
  let m : Map[String, String] = Map([])
  m[k] = v
  m
}

///|
test "默认：global 与 profile 合并，profile 覆盖 global" {
  let opts : EnvOptions = default_env_options()
  let inherited : Map[String, String] = Map([])
  let plan = plan_env_map(
    map1("FOO", "global"),
    map1("FOO", "profile"),
    opts,
    inherited,
    ":",
  )
  match plan.get("FOO") {
    Some(v) => assert_eq(v, "profile")
    None => assert_true(false)
  }
}

///|
test "override：继承值被 global 覆盖" {
  let opts : EnvOptions = { ..default_env_options(), merge: "override", }
  let plan = plan_env_map(
    map1("FOO", "global"),
    Map([]),
    opts,
    map1("FOO", "inherited"),
    ":",
  )
  match plan.get("FOO") {
    Some(v) => assert_eq(v, "global")
    None => assert_true(false)
  }
}

///|
test "append：继承值在前、global 值接在后面" {
  let opts : EnvOptions = { ..default_env_options(), merge: "append", }
  let plan = plan_env_map(
    map1("FOO", "global"),
    Map([]),
    opts,
    map1("FOO", "inherited"),
    ":",
  )
  match plan.get("FOO") {
    Some(v) => assert_eq(v, "inherited:global")
    None => assert_true(false)
  }
}

///|
test "不继承时没有可拼的东西，append 退化为覆盖" {
  let opts : EnvOptions = { keep_system: false, merge: "append", }
  let plan = plan_env_map(
    map1("FOO", "global"),
    Map([]),
    opts,
    map1("FOO", "inherited"),
    ":",
  )
  match plan.get("FOO") {
    Some(v) => assert_eq(v, "global")
    None => assert_true(false)
  }
}

///|
test "profile 永远覆盖 global，append 不再叠加" {
  let opts : EnvOptions = { ..default_env_options(), merge: "append", }
  let plan = plan_env_map(
    map1("FOO", "g"),
    map1("FOO", "p"),
    opts,
    map1("FOO", "i"),
    ":",
  )
  match plan.get("FOO") {
    Some(v) => assert_eq(v, "p")
    None => assert_true(false)
  }
}

///|
test "保留键与非法键名不进计划" {
  let opts : EnvOptions = default_env_options()
  let g : Map[String, String] = Map([])
  g["DSH_HOME"] = "/x"
  g["has space"] = "y"
  g["OK_KEY"] = "z"
  let plan = plan_env_map(g, Map([]), opts, Map([]), ":")
  assert_false(plan.contains("DSH_HOME"))
  assert_false(plan.contains("has space"))
  assert_true(plan.contains("OK_KEY"))
}
