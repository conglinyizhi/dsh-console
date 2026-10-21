// 应用状态、消息与更新循环。
//
// 导航既是状态切页也是 URL：page 是 model 里的字段，同时写进地址栏（见 route.mbt），
// 刷新与前进/后退都按地址复原页面。
// 三个只读接口在 init 里一次发出去；读不到就把原因留进 model，界面直接展示；
// 还没回来之前界面是加载态，不是空态（见 readings_pending）。

///|
pub(all) enum Page {
  Overview
  /// 维护（作业台）：按顺序做、每步有检查、失败能退回的作业都在这里
  Maintenance
  Logs
  Settings
  /// 回收站（第六轮）：删除进回收站的那些 profile 在这里看得见、能恢复、能彻底删掉
  Trash
  About
} derive(Eq)

pub extend Page with Eq::{ not_equal, equal }

///|
/// 行内动作通道的键（与现有 actions.ts 的 ActionKey 一一对应）。
priv enum ActionKey {
  OpenUi
  Toggle
  Restart
  CopyUrl
  /// 复制带令牌的地址：只在真有 webUrl 时出现（读不到令牌就不摆这一项）
  CopyTokenUrl
  /// 复制开发指令：把一段给「另一个会话」的任务说明写进剪贴板（粘贴到别的 profile 的会话里，
  /// 让那边针对这一只 profile 开发）。认不出 profile 目录名时不摆这一项。
  CopyDev
  Fork
  Rename
  /// 编辑这只 profile 的备注（POST set-profile-note）
  Note
  Archive
  Unarchive
  Delete
  /// 切到日志页并把来源设成这一行对应的实例（第三轮：不再落进兜底）
  Logs
  /// 打开这只 profile 的工作目录（POST open-path，kind=dir）
  Dir
  /// 打开这只 profile 的 cordis.patch.yml（POST open-path，kind=config）
  Config
  /// 隔离到独立 home（POST isolate-profile）
  IsolateHome
  /// 取消隔离（先开确认框，确认后 POST deisolate-profile）
  DeisolateHome
}

///|
/// 页脚那颗灯的三档（design/design-fixes.md §31.1）：
/// 还不知道（刚进页面）→ 在线 → 离线。颜色 + 文字两通道，不靠颜色单独表达。
priv enum ServerHealth {
  HealthChecking
  HealthOnline
  HealthOffline
} derive(Eq)

///|
/// 两档：真实读取失败退回演示 / 请求还在路上。
///
/// 「这一份是真读数」那一档已经删掉（使用者 2026-10-15 决定）：页面上读到的一切
/// 都是真读数，为「一切正常」再挂一个徽标，只是旧前端迁移到新前端时留下的历史产物。
/// 于是标记本身也跟着变成可选的 —— None 就是「读到了，没什么要说的」（见 SourceTag?）。
enum TagKind {
  /// 真实读取失败，这一份退回演示数据。**这一档必须留着**：
  /// 它说的是「你现在看到的是兜底数据」，删了失败就会伪装成正常。
  Fallback
  /// 读数还没回来：界面上说「读取中」
  Pending
} derive(Eq)

pub extend TagKind with Eq::{ not_equal, equal }

///|
/// 一处数据的数据源标记，界面上逐处标。
/// fallback = 真实读取失败，显式退回演示；pending = 请求还在路上
/// （这一档**不是**空数据：把「还在读」标成「没有」正是要修的那件事）。
///
/// 标记只在出岔子时才有：读到了就不摆徽标，模型里存 None（见各处的 tag_* 字段）。
struct SourceTag {
  kind : TagKind
  label : String
  detail : String
} derive(Eq)

pub extend SourceTag with Eq::{ not_equal, equal }

///|
/// 控件里正在编辑的文本。键与文本分开存，保存成功或失败都要能把它清掉。
struct SettingDraft {
  key : String
  text : String
} derive(Eq)

pub extend SettingDraft with Eq::{ not_equal, equal }

///|
/// 启动环境里正在编辑的那一格（design/design-fixes.md §61）。
///
/// scope 是**作用域 id**（"global" 或 "<home>|<profile>"）：同一个键名在全局与某只
/// profile 是两条不同的记录，混成一个 (键 → 文本) 的集合会互相盖掉。
struct EnvDraft {
  scope : String
  key : String
  text : String
} derive(Eq)

pub extend EnvDraft with Eq::{ not_equal, equal }

///|
/// 通知历史上最多留几条（design/design-fixes.md §36）：新到旧，超了就丢最旧的。
pub let notice_history_max : Int = 20

///|
struct Model {
  page : Page
  /// 地址回落说明：URL 认不出来时写在这里，由外壳顶部那条提示显示（空串 = 没有要说的）
  route_notice : String
  // 三个只读读数：原始事实 + 失败原因 + 读数时刻
  runtime : RuntimeFacts?
  runtime_error : String
  runtime_time : String
  profiles : ProfilesFacts?
  profiles_error : String
  instances : InstancesFacts?
  instances_error : String
  // 五处数据源标记。None = 这一份读到了真读数，界面上不摆任何徽标
  tag_runtime : SourceTag?
  tag_instances : SourceTag?
  tag_profiles : SourceTag?
  tag_archived : SourceTag?
  tag_settings : SourceTag?
  // 三个读数是否都落地了：都落地才拼一次列表（Vue 版是 Promise.all 之后拼）
  read_runtime : Bool
  read_profiles : Bool
  read_instances : Bool
  built : Bool
  rows : Array[Row]
  // 交互状态
  /// 详情抽屉开着的是哪一行（row.id）；空串 = 抽屉关着。
  ///
  /// 抽屉是**覆盖式**的（position: fixed 贴右侧，不占文档流），卡片因此不必为它让位。
  /// 关抽屉时焦点回到触发它的那张卡 —— 卡有稳定的 DOM id（见 card_id），不必再存一个返回值。
  drawer_id : String
  /// 正在滑出、还没撤节点的那一行（空串 = 没有）。**这一格只是一段动画的寿命**：
  /// 关上之后节点还留 drawer_anim_ms，让滑出看得见；到点由 DrawerClosed 撤掉。
  /// 它不参与任何判定 —— 焦点、点击、键盘都按「抽屉已经关了」走。
  drawer_closing : String
  /// 抽屉里「打开 Web UI」右段 chevron 那份菜单开着没有（§29.3）。
  /// 同一时刻只有一份（抽屉只开一行），所以一格布尔就够；抽屉一关、换行一并复位。
  split_menu_open : Bool
  // ── 拖动排序（第十轮） ──
  //
  // 状态分三块：**表**（order）、**这一次拖动的过程**（drag_*）、**写回失败的回滚点**
  // （order_before）。三块分开存，是因为它们的寿命不一样：表是读数级别的（刷新会重读），
  // 过程是一次手势级别的（松手就清），回滚点只活到回执回来那一刻。
  /// 手动排序的顺序表。空 = 没拖过 = 两组各走各的自动排序（见 apply_order）
  order : Array[String]
  /// 正在按下的那一行（"" = 没按）。窄屏按下时这一格不置 —— 那一档不启动拖动
  drag_id : String
  /// 按下那一刻的视口坐标：判「位移过没过阈值」用
  drag_start_x : Double
  drag_start_y : Double
  /// 位移过阈值了。**只有它成立才叫拖动**；没过的按下-松开仍然是点击（开抽屉）
  drag_active : Bool
  /// 这一次拖动落在哪一组（"" = 没有）。占位块只插在这一组里。
  drag_group : String
  /// 被拖的那一条原来在第几格（0 起）：换位播报要说「从第几到第几」时用得上。
  drag_from : Int
  /// 落点那一格现在是哪一条（"" = 现在没有落点）。
  ///
  /// 只是给人读的读数（拖动过程里「要落到谁那儿」），不参与摆放：
  /// 占位块与落位都按 drag_at_index 那一个格子序号走（见 drop_cell），
  /// 两者必须是同一个决定的两个说法，不然画在最左边而落在最右边。
  drag_at : String
  /// 上面那个占位块所在的**格子序号**（0 起），也就是松手后被拖的那一条将落到的位次。
  ///
  /// 这一格是这一轮的**唯一判据**：占位块画在第 k 格、松手就落在第 k 格。
  /// -1 = 没有落点（指针横向出了这一组的栅格 / 跨组 / 还没过阈值）。纵向**不设界**：
  /// 越过最后一块 = 最后一格、越过第一块 = 第一格（第十三轮口径变更）。
  drag_at_index : Int
  /// 拖动中的虚影跟着指针走到哪儿了（视口坐标；按下那一刻虚影的中心就压在指针上）。
  /// 只是画：不参与任何判定。
  drag_ghost_x : Double
  drag_ghost_y : Double
  /// 虚影要不要画（过了阈值才算拖动，虚影跟着出现）
  drag_ghost : Bool
  /// 虚影的宽高（CSS 像素）：按下时从被拖的那一条身上量一次，整个拖动过程不变。
  /// 中途不再量，是因为列表正在让位 —— 再量一次会量到挪开后的格子，虚影会跟着跳。
  drag_ghost_w : Double
  drag_ghost_h : Double
  /// 这一次按下-松开不该再开抽屉（拖动过了）。**下一次按下会把它清掉** ——
  /// 不这么做的话，「拖完在卡片外松手、click 没来」会把这个标记一直留着，
  /// 吃掉使用者下一次真正的点击。
  drag_suppress_click : Bool
  /// 键盘换位正等着落位的那一步（-1 / +1；0 = 没有等着的那一步）。
  ///
  /// Ctrl+方向键分两拍：先摆出占位块让人看见「要落到哪儿」，190ms 之后才真的换。
  /// 这一格记的就是那第二拍要走的步长 —— 不记的话，第二拍只能现猜，
  /// 而这中间使用者可能又按了别的方向（那时预览已经跟着换了，落位必须听最后一次）。
  drag_key_dir : Int
  /// 提交前的那一份顺序。写回失败要按它回滚：失败之后页面必须回到原样，
  /// 停在「看着是新的、其实没存下」的状态比不做还糟。
  order_before : Array[String]
  restarting : String
  rename_id : String
  rename_draft : String
  rename_return : String
  // 备注（POST /api/local/action 的 set-profile-note）。note_open 非空 = 编辑框开着：
  // 与重命名同一套（预填、Esc 取消、关闭后焦点回触发元素），只是内容是自由文本。
  note_open : String
  note_draft : String
  note_return : String
  /// 上一次保存失败的原因（后端给的原文）；空串 = 没有要报的错
  note_error : String
  /// 正在保存哪一行的备注；空串 = 没有在保存
  note_saving : String
  confirm_id : String
  confirm_return : String
  /// 点开删除确认框**那一刻**是哪种模式（true = 彻底删除，不进回收站）。
  ///
  /// 按当时记下来、按记下来的发请求（design/ops-maintenance-jobs.md §13.2）：
  /// 确认框开着的时候设置页可能把它改了，事后再去读一遍设置就是「靠事后猜」。
  confirm_hard : Bool
  // 移回共用 home 的确认框：目标行 id（空串 = 框关着）与触发元素 id。
  // 与删除确认框分开一格：两个框说的是两件事，共用一个字段会让「关掉一个，另一个也关了」。
  home_confirm_id : String
  home_confirm_return : String
  /// 正在移动的那一行（空串 = 没有在移）。抽屉里那颗按钮在这期间显示「正在移动…」并禁用 ——
  /// 移动是一次可能耗时（跨盘退回复制时尤其）的真实文件操作，按下去没反应最容易被再点一次。
  home_move_id : String
  // 配置历史的「还原」确认框（design/ops-maintenance-jobs.md §16.4）。
  // 与删除 / 取消隔离两个确认框分开三格：三个框说的是三件事，共用会让「关掉一个，另一个也关了」。
  /// 还原确认框正对着哪一行（空串 = 框关着）
  snapshot_confirm_id : String
  /// 那一行里要还原的那一份快照 id
  snapshot_confirm_snap : String
  /// 触发元素 id（关框之后焦点回到它）
  snapshot_confirm_return : String
  // 整体替换（design/ops-maintenance-jobs.md §17.3）：右侧栏里先选源，再出差异预览。
  // 三个状态分开存：目标那一行（侧栏关着时为空串）、选中的源、那份预览读数。
  /// 要替换的是哪一行（空串 = 侧栏关着）
  promote_row : String
  /// 打开侧栏的那颗按钮的 id（关掉之后焦点回它）
  promote_return : String
  /// 选中的源 profile 名（空串 = 还没选）
  promote_source : String
  /// 选中那只的预览读数。None + 正在读 = 读取中；None + 读完了 = 读失败（原因在 promote_preview_error）
  promote_preview : PromotePreview?
  /// 预览读不出来的原因（后端原话）；空串 = 没有要报的
  promote_preview_error : String
  /// 正在读预览
  promote_loading : Bool
  /// 确认框开着没有（§17.4 那颗「确认替换」之后的框）
  promote_confirm : Bool
  // 「＋新建实例」对话框（design/design-fixes.md §19.1）：同一个框里两步 —— 选源配置、填名字。
  /// 框开着没有（空 = 关着）
  new_open : Bool
  /// 选中的源 profile 名（空串 = 还没选）。选中那一张卡高亮，创建键按它可点。
  new_source : String
  /// 「从基础实例开始」这枚复选框勾着没有（design/design-fixes.md 第 20 / 21 节）：
  /// 勾着时创建走 create-base-profile，不派生、也不读任何现有配置；同时上面每一张源卡
  /// 都不可选（置灰 + aria-disabled + 点击无反应），名字框旁边给一句引导。
  /// 勾掉不碰名字框里的字，卡片恢复可选。
  new_base : Bool
  /// 名字输入框里的原文。选源时默认填 <源>-dev，勾上复选框时（只在它是空的时候）填 base-NN。
  new_name_draft : String
  /// 名字框脏标记（§21）：**只有输入事件**置位（预填不置位）。
  /// 勾上「从基础实例开始」时靠它判断「用户已经输入过任何字符」—— 输入过就一个字都不动，
  /// 哪怕现在又被删空了也不预填。勾掉同样不看它、不碰文本框。
  new_name_dirty : Bool
  /// 上一次创建失败的原因（后端原话）。框开着时写在框里，框不关。
  new_error : String
  /// 正在创建（请求已经发出去，两颗键都锁住，免得连点两次派生两份）
  new_busy : Bool
  /// 创建成功、等读数落地之后把焦点送到哪一只：存新 profile 名（空串 = 没有等着的那张卡）。
  /// 新卡是**重读 profiles 之后**才有的，所以焦点不能当场发 —— 由 rebuild 收这一格。
  new_focus : String
  // 回收站「彻底删除」的确认框：目标目录名（空串 = 框关着）与触发元素 id
  trash_purge_dir : String
  trash_purge_return : String
  // ── 维护页（作业台） ──
  // 动作结果从 §14 起走全局提示；这一页只留作业自己的状态（步骤表、预演记录、卡里的细节）。
  /// 新作业表单里的目标版本（空串 = 没选）。**不在本地补一个「最新版」**：
  /// §4 说得很清楚，版本由使用者选，后端不猜。
  /// 第六版起这一格只由版本侧栏回填：表里点一版、或按自定义版本那一行。
  job_version : String
  /// 版本侧栏开着没有（§12.1：从居中弹层改成右侧栏，与配置侧栏同一套外壳）。
  /// 开着的时候焦点在搜索框里。
  version_sidebar : Bool
  /// 侧栏搜索框里的原文：输入即过滤，列表里没有就是自定义版本。
  version_query : String
  /// 版本表上的过滤 chip（§12.3）。**空数组 = 「全部」**：一个都不选就是不过滤。
  /// 元素只认 "installed" / "stable" / "prerelease" 三个键，多个之间是「或」。
  version_filters : Array[String]
  /// 版本表的排序档（§12.3）：new（从新到旧，缺省）/ old（从旧到新）/ published（按发布时间）。
  version_sort : String
  /// 版本来源读数（GET /api/local/dsh-releases）。后端只读进程内缓存、秒回，
  /// 所以「慢」不再是这一页的问题：读到的 state 说的是后台那一趟拉取的状态。
  /// None + 还在问 = 读取中；None + 问完了 = 没读到（releases_error 里有原因）
  releases : ReleasesFacts?
  releases_error : String
  releases_loading : Bool
  /// 已经为「还在拉」补问了几次（进维护页 / 打开侧栏时清零）。
  /// 后端那条 GET 只回缓存，所以读到 loading 之后要隔一会儿再问一次才拿得到结果；
  /// 上限见 state.mbt 的 releases_poll_cap，免得某次真挂了把定时器挂成永动机。
  releases_ticks : Int
  /// 已经有一个补问的定时器排着了。**同一时刻只许排一个**：
  /// 进页面与打开侧栏会各发一次 GET，两个回执各排一个定时器的话，补问会翻倍
  /// （2、4、8…几拍就把上限吃完），列表还没落地就已经不再问了。
  releases_poll_pending : Bool
  /// 试跑用配置的右侧侧栏开着没有（§10.3）。开着的时候焦点在第一张可点的卡上。
  profile_sidebar : Bool
  /// 新作业表单里选的试跑 profile（空串 = 还没亲手选过，按「在跑的 → web → 第一份」推）。
  /// 存「用户亲手选的那一个」，不存推出来的那一个：推的那份随读数变，
  /// 存下来就成了「明明不是它却显示是它」。
  job_profile : String
  /// 正在发的那条作业动作："new" 或作业 id（空串 = 没有在发）
  job_busy : String
  /// 最近一次作业动作的**细节**（确切命令 / 包目录 / 输出尾部），写进那条作业的卡里。
  ///
  /// §14 之后动作结果走全局提示（一条结论），这里只留细节：两处各说一半，
  /// 同一句话就不会在页面上出现两遍。失败不写这一格 —— 失败的原因在全局提示条上，
  /// 历史留在后端写的步骤表里。
  job_detail : String
  /// 上面那段细节属于哪条作业（空串 = 没有要摆的）
  job_detail_for : String
  /// 被使用者亲手收起的作业 id。**默认全部展开** —— 收起是一个显式动作，
  /// 记下收起的那几条就够了；不必再维护一份「展开着哪些」（新作业进来时它会漏掉）。
  job_collapsed : Array[String]
  /// 已经预演过的那条作业 + 预演的是哪一步（install / cleanup）。
  /// 「预演之后才让点确认执行」靠它：没预演过，确认键是灰的。
  job_previewed : String
  job_previewed_step : String
  archived_open : Bool
  /// 用户手动折过归档区没有：折过之后就不再被 ui.archiveOpenByDefault 覆盖
  archived_user_toggled : Bool
  // 关于页「这台的 dsh 版本」（指定用哪一版起实例）
  //
  // 回执从 §14 起走全局提示：改完版本切到任何一页都看得见，不再借总览页的格子。
  /// 正在指定的那一份包目录（空串 = 没有在指定，按钮因此可点）
  dsh_pin_busy : String
  // 外壳的侧栏（design/sidebar-collapse.md）
  //
  // 两格说的是两件不同的事，寿命也不同：
  //   sidebar_collapsed  宽屏的形态（190px 展开 / 56px 图标栏）。**状态存在设置里**
  //                      （ui.sidebarCollapsed），这一格是它的界面副本 —— 设置读到、
  //                      这一项保存成功、恢复默认三条路都会把它同步过来（见 app.mbt）。
  //   sidebar_overlay    窄屏的覆盖层开着没有，**不持久化**：每次进来都是收起的。
  /// 宽屏侧栏是不是收成了图标栏
  sidebar_collapsed : Bool
  /// 窄屏侧栏覆盖层开着没有（宽屏不摆遮罩，这一格没有意义）
  sidebar_overlay : Bool
  // 设置页
  settings_loaded : Bool
  settings_loading : Bool
  settings : SettingsFacts?
  settings_error : String
  settings_status : Int
  settings_status_text : String
  settings_endpoint_missing : Bool
  /// 设置页的分组。**空串 = 没有指定分组**：窄屏按它画第一级（分区列表），
  /// 宽屏回落第一组。进第二级（/settings/<分组>）才写成具体 id。
  settings_group : String
  /// 控件里正在编辑的文本（键 → 草稿）：保存失败要把草稿退回已保存的值
  settings_draft : Array[SettingDraft]
  settings_saving : String
  /// 正在保存的那个键准备写入的值（回执里没带新值时按它记账）
  settings_pending : SettingValue?
  // ── 启动环境（design/design-fixes.md §61）──
  //
  // 与设置项分开：设置项是「一个键一个值」的封闭契约，这里是任意键值表（§61.5）。
  // 界面**不本地记账**：改一次就发 save-env，成功之后重读设置，以读数为准。
  /// env.json 的落点（后端给的原话，只用来在页面上说清「存在哪儿」）
  env_path : String
  /// 全局那一段（键值对，顺序照读数）
  env_global : Array[(String, String)]
  /// 每只 profile 单独设的那一份：键是 "<home>|<profile>"，与行 id 同一口径
  env_profiles : Array[(String, Array[(String, String)])]
  /// 控制台自己管、不许被覆盖的键（DSH_HOME / PATH …）
  env_reserved : Array[String]
  /// 现在按明文显示的那些值。键是「作用域 id + | + 键名」——
  /// 同一个键名在全局与某只 profile 是两条，混成一个集合会一起露出来
  env_shown : Array[String]
  /// 正在编辑的值（控件里的原文）。保存成功之后清空，退回读数里的那一份
  env_draft : Array[EnvDraft]
  /// 「添加一行」两个输入框里的原文（键 / 值）
  env_add_key : String
  env_add_value : String
  /// 抽屉里「这只 profile 的启动变量」对话框指着哪一行（空串 = 关着）
  env_open : String
  /// 这只在跑的实例，启动变量是不是已经**解锁修改**（M / 只读档）。
  ///
  /// 默认 false：实例在跑时那张表先按只读摆（改完要下次启动才生效，先让人看清
  /// 进程里到底绑了什么）。点「仍然修改」才置 true。每次开 / 关对话框都清零 ——
  /// 解锁是**这一次**的决定，不该跟着下一只 profile 一起过去。
  env_edit_unlocked : Bool
  /// 读数里有没有 options 段（§62.2）。false = 后端还没这一版：
  /// 界面不摆「继承 / 同名变量」那两项，保存也不带 options（旧后端会整枪拒掉参数）
  env_options_known : Bool
  /// 继承控制台进程自己的环境变量（缺省 true）
  env_inherit : Bool
  /// 继承值与 global 撞上时：override 覆盖 / append 追加（缺省 override）
  env_merge : String
  // 写动作（POST /api/local/action）
  /// 正在等响应的启动动作所在的行；空串表示没有
  act_pending : String
  /// 这一次启动的响应到了没有
  act_response : Bool
  /// 启动的展示计时到了没有（等待态至少显示 start_delay_ms）
  act_tick : Bool
  act_ok : Bool
  act_note : String
  // 动作结果的唯一出口（design/ops-maintenance-jobs.md §14）。
  //
  // 删掉了五组各自为政的格子（总览的 act_notice、设置页的 settings_feedback、
  // 关于页的 dsh_pin_notice、版本侧栏的 releases_refresh_error，以及它们各自的
  // ok / hint 尾巴）：谁都只管自己那一页，切一页就看不见了。
  /// 现在这条提示。None = 没有。成功与失败都走它：成功是底部 toast（3.5 秒后自己走），
  /// 失败是常驻提示条（直到下一条动作替换它，不自动消失）。
  notice : Notice?
  /// 已经发过几条。每发一条 +1，Notice.seq 取的就是它 ——
  /// 提示被收掉之后这格仍然往前走，旧的到期消息回来才认得出「那一条早就不在了」。
  notice_serial : Int
  // 页脚「服务端在线」灯（design/design-fixes.md §31.1）
  //
  // 这几格**只由那条 5 秒一次的探测写**：profiles / instances / console 那几份读数
  // 各有各的请求与错误格，这一枪失败不许改它们 —— 灯说的是「服务端答不答」，
  // 不是「读数好不好」。
  /// 三档：还在检查 / 在线 / 离线
  health_state : ServerHealth
  /// 最近一次成功探测的往返毫秒（本机量的）；还没成功过是 0
  health_ms : Int
  /// 最近一次探测落地的本地时刻 HH:MM:SS（成功失败都记；悬停里说「检查于」）
  health_at : String
  /// 连续失败了几次（成功一次就归零）
  health_fails : Int
  /// 最近一次失败的原因（成功时清空）
  health_reason : String
  /// 一次探测还在路上：挡住重入，别让两枪同时飞
  health_busy : Bool
  /// 已经挂了一个「等页面重新可见」的监听（别重复挂）
  health_visible_wait : Bool
  /// 启动等待态里那句提示要用的两个词（回执与计时是两条路，各自都拿得到它们）：
  /// 谁（web-dev）与做了什么（启动）。组句见 app.mbt 的 action_receipt。
  act_name : String
  act_verb : String
  // 启动成功后自动开标页（占位页模式，见 dom.mbt 的 js_tab_hold）
  /// 点击启动时同步开的占位标页的结局：'held' / 'blocked' / 'error: …'；
  /// 空串 = 这一次点击没有开标页（读数里没有 profile 目录名，请求都没发出去）
  start_tab : String
  /// 那只占位标页是为哪个 profile 开的：启动成功之后按它去 instances 读数里找 webUrl
  start_tab_profile : String
  /// 启动成功、还在等 instances 读数把带令牌的地址给出来（拿到就填进占位标页）
  start_tab_waiting : Bool
  /// 等地址时重读了几轮读数（有界，见 start_tab_max_tries）
  start_tab_tries : Int
  /// 命令行型 profile 那句说明开着没有（§42）：值是那一行的 id，空串 = 关。
  cli_help_id : String
  /// 提示条里那颗「打开 Web UI」要开的地址（方案 B：用户再点一下 = 新手势，
  /// 一定不被弹窗拦截器吃掉）。None = 不摆按钮。
  notice_url : String?
  /// 上面那个地址属于哪一条提示条文字（Notice.text）。与当前那条不一致时按钮不出现 ——
  /// 提示条被别的动作改写之后，按钮自己失效，不留一个对不上号的入口。
  notice_url_notice : String
  /// 最近的通知历史（§36）：新到旧，最多 notice_history_max 条。只在内存里，刷新就清空。
  notice_history : Array[NoticeRecord]
  /// 上一次打开通知侧栏之后又来了几条（铃铛上的角标）。打开侧栏就归零。
  notice_unread : Int
  /// 通知侧栏开着没有（右侧面板，盖在抽屉之上、确认框之下）
  notice_panel : Bool
  /// 分发插件对话框说的是哪一行（design/backlog.md N）。空串 = 框没开
  merge_source : String
  /// 选中的目标 profile 名（多选）
  merge_targets : Array[String]
  /// 确认串输入框里的原文（要打成 MERGE）
  merge_confirm : String
  /// 正在分发
  merge_busy : Bool
  /// 滑动确认的进度（0..100，到 95 以上才提交）
  merge_slide : Int
  /// 对话框当前第几步（1 = 选插件，2 = 选目标）
  merge_step : Int
  /// 正在拖滑块：只有按下之后才跟随指针
  merge_dragging : Bool
  /// 预览接口读回来的插件：名字 / 版本 / 形态（local-dir / local-link / registry / missing）
  merge_plugins : Array[(String, String, String, String)]
  /// 勾中的插件名
  merge_plugin_picked : Array[String]
  /// 预览还在读
  merge_loading : Bool
  /// 关框后焦点回哪颗按钮
  merge_return : String
  /// 派生副本前的确认框说的是哪一行（§60.2）。空串 = 框没开
  fork_confirm_id : String
  /// 打开确认框那颗按钮的 DOM id：关框之后焦点回它
  fork_confirm_return : String
  /// 派生拷贝进度（§72）：跑的过程中摆一只进度框，拷完自动关。
  fork_progress_active : Bool
  fork_progress_name : String
  fork_progress_files : Int
  fork_progress_total : Int
  fork_progress_error : String
  /// 补包确认框说的是哪一行（§39.1）。空串 = 框没开
  repair_confirm_id : String
  /// 打开确认框那颗按钮的 DOM id：框关掉之后焦点回它
  repair_confirm_return : String
  /// 正在补包的那一行：按钮写「正在安装…」，别的写动作跟着 row.busy 一起禁用
  repair_id : String
  // 成功 toast 的两格过程状态（外观见 view_shell 的 global_notice，计时见 app.mbt 的 update）
  /// 鼠标正停在提示上：这一拍不许它消失（悬停时别让它正好在眼皮底下走掉）
  flash_hover : Bool
  /// 正在淡出（去掉节点前的最后一小段，见 flash_fade_ms）
  flash_fading : Bool
  // 控制台自己的状态读数（GET /api/local/console）：运行时登记 + 归档记录
  console : ConsoleFacts?
  console_error : String
  read_console : Bool
  // 日志页
  log_source : String
  log_user_picked : Bool
  /// 日志请求还在路上。**「还没读完」与「确实是空的」是两副样子**，界面按它分档。
  log_loading : Bool
  /// 现在 logs 里那份内容是哪个来源读回来的（空串 = 还没读到过）。
  /// 换了来源之后旧内容不能顶着新来源显示，要不要重读就看它。
  log_source_read : String
  /// 从失败提示条跳过来（§32.1）：日志落地之后要把焦点送进日志区。
  /// 打开那一刻日志区还不存在（先渲染加载态），所以这件事只能等读数回来再做。
  log_focus_pending : Bool
  logs : LogsFacts?
  log_error : String
  log_time : String
  log_tag : SourceTag?
  log_instance_note : String
} derive(Eq)

pub extend Model with Eq::{ not_equal, equal }

///|
priv enum Msg {
  RuntimeText(Result[String, Error])
  ProfilesText(Result[String, Error])
  ConsoleText(Result[String, Error])
  InstancesText(Result[String, Error])
  LogsText(Result[String, Error])
  Navigate(Page)
  /// 宽屏顶栏的折叠按钮：翻一下侧栏形态，并把新形态写进设置（ui.sidebarCollapsed）
  SidebarToggle
  /// 窄屏顶栏的汉堡：侧栏以覆盖层滑出，焦点进第一个导航项
  SidebarOverlayOpen
  /// 收起窄屏覆盖层（Esc / 点遮罩；点导航项与切页在 Navigate 里一起收）
  SidebarOverlayClose
  /// 浏览器前进 / 后退（或手改了 path）：按当前地址复原页面，不写历史
  RouteChanged
  RowAction(String, ActionKey)
  /// 抽屉里「硬开裸地址」那一枪的回执：js_open_url 在 DOM 监听器里同步打完，
  /// 结局（'ok' / 'blocked' / 'error: …'）与那一刻的裸地址随这条消息进 model
  /// （design/ops-maintenance-jobs.md §15.2）
  HardOpenDone(String, String, String)
  /// 启动按钮的点击：行 id / profile 目录名 / 占位标页的结局。
  /// 占位标页是在 DOM 监听器里**同步**开好的（见 view_overview 的 start_click），
  /// 回执随这条消息进来 —— update 走 queueMicrotask，等不到用户手势那一栈。
  StartClicked(String, String, String)
  /// 启动成功但带令牌的地址还没到：再重读一轮读数（有界，见 start_tab_max_tries）
  StartTabRetry
  /// 提示条里那颗「打开 Web UI」被点了（方案 B 的兜底入口）
  NoticeOpenUi
  /// 失败提示条里那颗「查看日志」被点了：跳 /logs/audit，选中审计来源、滚到底、焦点进日志区
  NoticeOpenLogs
  /// 抽屉「操作」组点了「分发插件…」：开对话框（design/backlog.md N）
  MergeOpen(id~ : String, return_id~ : String)
  /// 目标勾/取消勾（profile 名）
  MergeTargetToggle(String)
  /// 滑动确认：指针/键盘把滑块推到某个百分比
  /// 两步之间切换（1 选插件 / 2 选目标）
  MergeStepNext
  MergeStepPrev
  MergeSlideStart
  MergeSlide(Int)
  /// 松开滑块：到 95 以上才提交，否则弹回左端
  MergeSlideRelease
  /// 键盘操作（方向键 / End / Enter）
  MergeSlideKey(String)
  /// 点「分发」：发 merge-plugins
  MergeSubmit
  /// 点「取消」（或 Esc / 遮罩）
  MergeCancel
  /// 预览接口的回执（插件清单）
  MergePreviewText(Result[String, Error])
  /// 勾/取消一只插件
  MergePluginToggle(String)
  /// merge-plugins 的回执
  MergeDone(Result[String, Error])
  /// 「派生开发副本」但这一只有外部软链接（§60.2）：先开确认框，不直接发请求
  ForkOpen(id~ : String, return_id~ : String)
  /// 确认框里点了「仍然派生」
  ForkConfirm
  /// GET /api/local/fork-progress 的回执（§72）：空串表示这一次读失败
  ForkProgressText(String)
  /// 下一拍再读一次进度
  ForkProgressTick
  /// 确认框里点了「取消」（或 Esc / 遮罩）
  ForkCancel
  /// 抽屉里点了「安装缺的包（N）」：开确认框（写 node_modules 算真动作）
  RepairOpen(id~ : String, return_id~ : String)
  /// 确认框里点了「取消」（或遮罩 / Esc）
  RepairCancel
  /// 确认框里点了「安装」：发 repair-packages
  RepairConfirm
  /// 顶栏「通知」：开侧栏看历史（顺手把未读角标清零，焦点进关闭键）
  NoticePanelOpen
  /// 关掉通知侧栏（关闭键 / 遮罩 / Esc 三条路），焦点回顶栏那颗铃铛
  NoticePanelClose
  /// 成功提示（toast）到点了：序号对得上才收
  FlashExpire(Int)
  /// 淡出那一小段走完，节点可以撤了
  FlashRemove(Int)
  /// 鼠标进 / 出 toast（进去之后不许它正好消失）
  FlashHover(Bool)
  /// 点整张卡：开详情抽屉（第七轮 —— 卡片上不再有按钮与 ⋯ 菜单，点卡是唯一入口）
  DrawerOpen(String)
  // 拖动排序（第十轮）：全程走指针事件。按下 / 移动 / 松开 / 取消四拍分开，
  // 「这一拍算点击还是算拖动」由 update 里的阈值判，视图只负责把事件送进来。
  /// 指针在某一行上按下（行 id / 视口坐标）
  DragDown(String, Double, Double)
  /// 指针移动（视口坐标 + 按键位掩码）。
  ///
  /// 位掩码不是装饰：松手若发生在**页面之外**（指针抬到窗口外面），那一下收不到，
  /// 拖动状态就会一直挂着（那一拍再划过列表，落位线还会跟着走）。
  /// 位掩码为 0 = 没有任何键按着 —— 那就是「其实早就松手了」，当场作废。
  DragMove(Double, Double, Int)
  /// 指针松开：占位块在哪一格就落到哪一格，立刻写回
  DragUp
  /// 指针被取消（触控被打断等）：这一次拖动作废，顺序一个字节都不动
  DragCancel
  /// 键盘换位第一拍：行 id + 方向（-1 往上 / +1 往下）。键盘用户没有鼠标，这条是他们的入口。
  /// 它**只摆占位块**，不动顺序 —— 让人先看见要落到哪儿，第二拍才落
  ReorderKey(String, Int)
  /// 键盘换位第二拍：预览摆够了，真的换。带方向，好与预览那一拍对上号
  ReorderCommit(Int)
  /// set-row-order 的回执：成功了保持新顺序，失败了回滚并如实报错
  OrderDone(Result[String, Error])
  /// 关抽屉：点外部 / Esc / 关闭按钮都走这一条。焦点回触发它的那张卡。
  DrawerClose
  /// 页脚那颗灯：到点了，发一次探测（页面隐藏时改成「等可见」）
  HealthTick
  /// 探测的回执（原始 JSON 文本；解析在 update 里做）
  HealthDone(Result[String, Error])
  /// 页面重新可见了：清掉「在等」的标记，立刻补一次检查
  HealthVisible
  /// 「打开 Web UI」右段 chevron：那份菜单开 / 收。展开时焦点落进菜单项，
  /// 收起时回 chevron（菜单项一撤，焦点不能掉到 body 上）。
  SplitMenuToggle
  /// 收起那份菜单（点外部 / Esc / 选了菜单项）。焦点回 chevron。
  SplitMenuClose
  /// 命令行型 profile 的「启动」被点：弹一句说明（§42）。带这一行的 id。
  CliHelpOpen(String)
  /// 关掉那句说明（按钮 / Esc / 点遮罩）。
  CliHelpClose
  /// 抽屉滑出那一段走完了，节点可以撤了（带的是正在收的那一行的 id：
  /// 号对不上说明这中间抽屉又开了，那一枪作废）。
  DrawerClosed(String)
  StartTick(String)
  RestartTick
  RenameInput(String)
  RenameConfirm
  RenameCancel
  // 备注：打开（带触发元素 id）/ 输入 / 保存 / 取消
  NoteOpen(String)
  NoteInput(String)
  NoteConfirm
  NoteCancel
  /// 打开删除确认框：目标行 id + 触发元素 id + **点下去那一刻是不是彻底删除**
  /// （Shift 按住，或回收站关掉）。第三格按当时定，确认框的三处文案与请求都照它走。
  DeleteOpen(String, String, Bool)
  DeleteConfirm
  DeleteCancel
  // 配置 home（design/deep-home-isolation.md）：移到独立 home / 移回共用 home。
  // 移动本身不改配置内容，点了就发（走 RowAction 里的 IsolateHome）；
  // 取消隔离是破坏性动作，先开确认框 —— 这三条是那个框的三拍。
  HomeDeisolateOpen(String, String)
  HomeDeisolateConfirm
  HomeDeisolateCancel
  // 配置历史（design/ops-maintenance-jobs.md §16.4）：创建快照（行 id）/ 还原（先开确认框）。
  // 还原确认框的三格是行 id / 快照 id / 触发元素 id。
  SnapshotCreate(String)
  SnapshotRestoreOpen(String, String, String)
  SnapshotRestoreConfirm
  SnapshotRestoreCancel
  // 整体替换（design/ops-maintenance-jobs.md §17.3）：打开侧栏（带目标行 id）/
  // 选中一只源 / 预览回执 / 开确认框 / 确认替换 / 取消 / 关侧栏
  PromoteOpen(String)
  PromoteSourcePicked(String)
  PromotePreviewDone(Result[String, Error])
  PromoteConfirmOpen
  PromoteConfirm
  PromoteConfirmCancel
  /// 预览之后回去重新选源（同一侧栏，切回卡片那一屏）
  PromoteBack
  PromoteClose
  // 回收站（第六轮）：恢复某一条 / 点「彻底删除」先开确认框 / 框里的确定与取消
  TrashRestore(String)
  TrashPurgeOpen(String, String)
  TrashPurgeConfirm
  TrashPurgeCancel
  // 维护页（作业台）：开始表单 / 展开步骤表 / 某条作业的一步 / 回执
  /// 打开版本侧栏：清空搜索框，焦点进搜索框，顺手再读一次后端缓存
  VersionSidebarOpen
  VersionSidebarClose
  /// 侧栏搜索框里的文本（输入即过滤）
  VersionQueryInput(String)
  /// 点一枚过滤 chip：带上那一枚的键（installed / stable / prerelease / all）
  VersionFilterToggle(String)
  /// 换排序档：new / old / published
  VersionSortPicked(String)
  /// 从侧栏里选中一版（写进 job_version）并关掉侧栏
  JobVersionPicked(String)
  /// 打开 / 关闭试跑用配置的右侧侧栏
  ProfileSidebarOpen
  ProfileSidebarClose
  /// 版本来源读数的回执（三个源的结果在里面，包括全都没答上来的那种）
  ReleasesText(Result[String, Error])
  /// 「还在拉」时补问一次的定时器到点了（上限见 state.mbt 的 releases_poll_cap）
  ReleasesTick
  /// 版本侧栏底部「重新拉取」：排一趟后台刷新，结果照旧靠轮询接上
  ReleasesRefresh
  /// 上面那一枪的回执（POST refresh-releases；成没排上都在这里判）
  ReleasesRefreshDone(Result[String, Error])
  JobProfilePicked(String)
  /// 维护页空态里那颗「开始一条作业」：把焦点送到表单的「当前版本」那一格
  /// （design/design-fixes.md 第 3 条）。不改任何读数，只挪焦点与视口。
  JobStartFocus
  /// 总览空态里那颗「刷新读数」：重发 profiles + instances 两份读数。
  /// 与写动作成功之后那一条走同一个函数（refresh_readings），不另开一条刷新路。
  RefreshReadings
  JobStart
  /// 作业 id + 这一步的动作（install-preview / install-confirm / test /
  /// commit / cleanup-preview / cleanup / abort）。后端动作名在 app.mbt 里映射。
  JobAction(String, String)
  /// 展开 / 收起一条作业的步骤表
  JobToggle(String)
  /// 作业动作的回执：动作名 + 原始响应（成败与文案在 update 里判）
  JobDone(String, Result[String, Error])
  ToggleArchived
  LogSourcePicked(String)
  LogRefresh
  // 设置页
  SettingsText(Result[String, Error])
  SettingsSaved(String, Result[String, Error])
  SettingsRetry
  SettingsGroupPicked(String)
  /// 窄屏第二级的返回键：回第一级（/settings），焦点回刚才那一行
  SettingsBack
  SettingDraft(String, String)
  SettingCommit(String, String)
  SettingToggle(String, Bool)
  /// 把这一项写回后端给的缺省值（见 app.mbt 的 reset_setting）
  SettingReset(String)
  // 启动环境（design/design-fixes.md §61.3）：改值 / 删行 / 添行 / 显示隐藏 /
  // 开关这只 profile 的对话框 / 回执。
  //
  // 四个写动作都带 scope（"global" / "profile"）而不带 home、profile 两个串：
  // profile 那一档的作用域由**开着的对话框**（env_open）决定，界面只摆得出一只；
  // 消息里再塞一遍路径，两处一旦不一致就会写到另一只 profile 名下。
  /// 值输入框里的原文（不打码的那一格正在被改）
  EnvDraft(String, String, String)
  /// 改值：改完即发 save-env（整份替换这个作用域）
  EnvCommit(String, String, String)
  /// 删掉一行
  EnvDelete(String, String)
  /// 「添加一行」：用 model 里那两个输入框的内容
  EnvAdd(String)
  /// 「添加一行」那两个输入框里的原文（键 / 值）。与 EnvDraft 分开两条：
  /// 它们不属于任何一行，保存成功之后就清掉，不跟着表格的草稿一起走
  EnvAddKeyInput(String)
  EnvAddValueInput(String)
  /// 勾 / 勾掉「继承系统环境变量」（§62.3）：改动即保存，与 global 那张表一起发
  EnvInheritToggled(Bool)
  /// 选「同名变量：覆盖 / 追加」（override / append）
  EnvMergePicked(String)
  /// 显示 / 隐藏一个值（只改本地状态，不写文件）
  EnvReveal(String, String)
  /// 打开抽屉里这只 profile 的启动环境对话框（带行 id）
  EnvProfileOpen(String)
  EnvProfileClose
  /// 这只在跑：只读档上那颗「仍然修改」—— 解锁本次编辑（不改任何读数，只翻本地一格）
  EnvEditUnlock
  /// save-env 的回执：作用域 + 原始响应（成败与文案在 update 里判）
  EnvSaved(String, Result[String, Error])
  // 写动作的回执：row_id / action / 谁 / 做了什么（动词）/ 原始响应
  HttpDone(String, String, String, String, Result[String, Error])
  // 复制到剪贴板的回执：复制的是谁的那一条地址 / 传输层拿回来的那段 JSON
  CopyDone(String, Result[String, Error])
  // 关于页「这台的 dsh 版本」：把某一份指定成起实例用的那一版 / 撤掉指定回到自动。
  // 带的是包目录与版本号 —— 回执要说清「以后起实例用的是哪一版」，不能只说「成功了」。
  DshVersionPin(String, String)
  DshVersionUnpin
  // 「＋新建实例」对话框（design/design-fixes.md §19.1）：开 / 选源 / 输入名字 / 创建 / 取消 / 回执。
  // 创建走既有的 fork-profile（新副本默认隔离），回执单开一条 NewInstanceDone：
  // 它要塞进框里的失败原因，与别的动作那条通用回执不是同一个去处。
  NewInstanceOpen
  NewInstanceClose
  NewInstanceStatePicked(String)
  NewInstanceNameInput(String)
  NewInstanceConfirm
  NewInstanceDone(Result[String, Error])
  /// 勾 / 勾掉「从基础实例开始」这枚复选框（design/design-fixes.md 第 21 节）。
  /// 带的是勾完之后的那一档：真 = 走基础模板、源卡全部锁上、焦点进名字格；
  /// 假 = 源卡恢复可选、名字框一个字不动。
  NewInstanceBaseToggled(Bool)
  /// 从基础模板新建的回执。与 NewInstanceDone 分开一条：它判的是另一组字段
  /// （name / home），重建回执时不能与派生的 newName / profile 混着读。
  NewInstanceBaseDone(Result[String, Error])
  Noop
}

///|
fn initial_model() -> Model {
  {
    page: Overview,
    route_notice: "",
    runtime: None,
    runtime_error: "",
    runtime_time: "—",
    profiles: None,
    profiles_error: "",
    instances: None,
    instances_error: "",
    // 初始那几副标记是「读取中」，不是「演示数据」：请求还在路上，
    // 这时候标成演示数据与标成空数据是同一个毛病 —— 把「还没读到」说成了别的。
    tag_runtime: pending_tag("控制台自身的读数还没回来"),
    tag_instances: pending_tag("实例读数还没回来"),
    tag_profiles: pending_tag("profile 读数还没回来"),
    tag_archived: pending_tag("归档与回收站读数还没回来"),
    tag_settings: pending_tag("设置读数还没回来"),
    read_runtime: false,
    read_profiles: false,
    read_instances: false,
    built: false,
    rows: [],
    drawer_id: "",
    drawer_closing: "",
    split_menu_open: false,
    health_state: HealthChecking,
    health_ms: 0,
    health_at: "",
    health_fails: 0,
    health_reason: "",
    health_busy: false,
    health_visible_wait: false,
    order: [],
    drag_id: "",
    drag_start_x: 0.0,
    drag_start_y: 0.0,
    drag_active: false,
    drag_group: "",
    drag_from: -1,
    drag_at: "",
    drag_at_index: -1,
    drag_ghost_x: 0.0,
    drag_ghost_y: 0.0,
    drag_ghost: false,
    drag_ghost_w: 0.0,
    drag_ghost_h: 0.0,
    drag_key_dir: 0,
    drag_suppress_click: false,
    order_before: [],
    restarting: "",
    rename_id: "",
    rename_draft: "",
    rename_return: "",
    note_open: "",
    note_draft: "",
    note_return: "",
    note_error: "",
    note_saving: "",
    confirm_id: "",
    confirm_return: "",
    // 没点开过确认框：这一格没有意义，缺省按「进回收站」那一支（框真开时会被覆盖）。
    confirm_hard: false,
    home_confirm_id: "",
    home_confirm_return: "",
    home_move_id: "",
    snapshot_confirm_id: "",
    snapshot_confirm_snap: "",
    snapshot_confirm_return: "",
    promote_row: "",
    promote_return: "",
    promote_source: "",
    promote_preview: None,
    promote_preview_error: "",
    promote_loading: false,
    promote_confirm: false,
    new_open: false,
    new_source: "",
    new_base: false,
    new_name_draft: "",
    new_name_dirty: false,
    new_error: "",
    new_busy: false,
    new_focus: "",
    trash_purge_dir: "",
    trash_purge_return: "",
    job_version: "",
    version_sidebar: false,
    version_query: "",
    version_filters: [],
    version_sort: "new",
    releases: None,
    releases_error: "",
    releases_loading: false,
    releases_ticks: 0,
    releases_poll_pending: false,
    profile_sidebar: false,
    job_profile: "",
    job_busy: "",
    job_detail: "",
    job_detail_for: "",
    job_collapsed: [],
    job_previewed: "",
    job_previewed_step: "",
    // 归档区默认折叠：这一组目前固定是演示数据，短时间用不上；
    // 折叠起来不占视线，功能本身留着（展开即可用），比删掉合适。
    archived_open: false,
    archived_user_toggled: false,
    dsh_pin_busy: "",
    // 首帧按展开画。设置回执一到（启动时就发了一次）就换成存下来的那一份 ——
    // 于是刷新之后看到的是折叠过的侧栏，不是先展开再收一下。
    sidebar_collapsed: false,
    sidebar_overlay: false,
    settings_loaded: false,
    settings_loading: false,
    settings: None,
    settings_error: "",
    settings_status: 0,
    settings_status_text: "",
    settings_endpoint_missing: false,
    // 首帧是「没有指定分组」：窄屏落第一级（分区列表），宽屏回落第一组。
    settings_group: "",
    settings_draft: [],
    settings_saving: "",
    settings_pending: None,
    // 启动环境：还没读到之前是空表（不是演示数据）。值为空 = 这一份没设过
    env_path: "",
    env_global: [],
    env_profiles: [],
    env_reserved: [],
    env_shown: [],
    env_draft: [],
    env_add_key: "",
    env_add_value: "",
    env_open: "",
    env_edit_unlocked: false,
    // 生效方式：还没读到 options 段时按缺省摆（inherit=true / override），
    // 但界面不摆这两项 —— env_options_known 才是「后端有没有这一版」的判据。
    env_options_known: false,
    env_inherit: true,
    env_merge: "override",
    act_pending: "",
    act_response: false,
    act_tick: false,
    act_ok: false,
    act_note: "",
    notice: None,
    notice_serial: 0,
    act_name: "",
    act_verb: "",
    start_tab: "",
    start_tab_profile: "",
    start_tab_waiting: false,
    start_tab_tries: 0,
    cli_help_id: "",
    notice_url: None,
    notice_url_notice: "",
    notice_history: [],
    notice_unread: 0,
    notice_panel: false,
    merge_source: "",
    merge_targets: [],
    merge_confirm: "",
    merge_busy: false,
    merge_slide: 0,
    merge_step: 1,
    merge_dragging: false,
    merge_plugins: [],
    merge_plugin_picked: [],
    merge_loading: false,
    merge_return: "",
    fork_confirm_id: "",
    fork_confirm_return: "",
    fork_progress_active: false,
    fork_progress_name: "",
    fork_progress_files: 0,
    fork_progress_total: 0,
    fork_progress_error: "",
    repair_confirm_id: "",
    repair_confirm_return: "",
    repair_id: "",
    flash_hover: false,
    flash_fading: false,
    console: None,
    console_error: "",
    read_console: false,
    log_source: "host",
    log_user_picked: false,
    log_loading: false,
    log_source_read: "",
    log_focus_pending: false,
    logs: None,
    log_error: "",
    log_time: "",
    log_tag: pending_tag("日志还没读"),
    log_instance_note: "",
  }
}

// ── 数据源标记 ──────────────────────────────────────────────

///|
/// 读失败那一档的标记（读成功那一侧写 None，不摆任何徽标）。
///
/// 返回的就是模型字段的值（SourceTag?），省得每个调用点再套一层 Some ——
/// 这一档只可能以标记的形式存在。
fn fallback_tag(detail : String) -> SourceTag? {
  Some({ kind: Fallback, label: "演示数据 | 真实读取失败", detail })
}

///|
/// 请求还在路上：读数没到之前的那一档。与「演示数据 / 读取失败」分开 ——
/// 那两档说的是「已经知道了什么」，这一档说的是「还不知道」。
fn pending_tag(detail : String) -> SourceTag? {
  Some({ kind: Pending, label: "读取中", detail })
}

///|
/// 几个只读读数是不是还没落地（runtime / profiles / instances / console 都算，
/// 列表就是等它们一起到了才拼的）。落地之前界面摆加载态：
/// 这一段空白不是「没有实例」，是「还没读到」。
fn readings_pending(model : Model) -> Bool {
  !model.built
}


// ── 拉取 ────────────────────────────────────────────────────

///|
fn load(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.batch([
    load_runtime(emit),
    load_console(emit),
    load_readings(emit),
  ])
}

///|