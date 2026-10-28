# 接口备忘（从 Android 源码里挖出来的）

这份文档是移植时从 `xjtu-toolbox-android` 的 `shared/data`（OkHttp + Jsoup）里逐条读出来的契约，
用于后续补完 iOS 版。所有路径、字段名都来自源码，**没有实机验证**的地方已标注。

---

## 1. 统一身份认证（已实现）

见 `Core/Auth/CASLogin.swift`，与 `XJTULogin.kt` 对齐：

| 步骤 | 请求 |
|---|---|
| RSA 公钥 | `GET https://login.xjtu.edu.cn/cas/jwt/publicKey`（Referer 为 CAS 登录页） |
| 打开登录页 | `GET https://login.xjtu.edu.cn/cas/login?service=<urlencoded>`，跟随 302，落点即 `postURL` |
| MFA 探测 | `POST /cas/mfa/detect`，form：`username`、`password`（`__RSA__…`）、`fpVisitorId` → `{"data":{"state","need"}}` |
| 取手机号 | `GET /cas/mfa/initByType/securephone?state=<state>` → `{"code":0,"data":{"gid","securePhone"}}` |
| 发短信 | `POST https://login.xjtu.edu.cn/attest/api/guard/securephone/send`，JSON `{"gid"}` |
| 校验短信 | `POST .../valid`，JSON `{"gid","code"}`，要求 `code==0` 且 `data.status=="2"` |
| 提交密码 | `POST <postURL>`，form：`username`、`password`、`execution`、`_eventId=submit`、`submit1=Login1`、`fpVisitorId`、`captcha`、`currentMenu=1`、`failN`、`mfaState`、`geolocation=`、`trustAgent` |
| 二次认证 | 页面含 `input[name=secState]`：先 `GET /cas/sec/initByType/securephone?state=<secState>` 拿 gid，验码通过后把 `secState/execution/_eventId/submit` POST 回**触发页 URL**（带 Referer） |
| 账户选择 | 页面含身份选项时 POST `https://login.xjtu.edu.cn/cas/login`（不带 service），`execution` 用选择页上的新值，`username=<选项值>`、`useDefault=false` |

要点：
- **UA 必须全程一致**（TGC 与 UA 绑定）。现用安卓客户端那串 Chrome/131。
- `fpVisitorId` = `SHA256("ios|Apple|<model>|<idfv>")` 前 32 位十六进制，存 Keychain。
- 失败 3 次后 CAS 要图形验证码，但源码里**没有取图接口**，只能让用户手输。

---

## 2. 校园卡（未实现）

Base：`https://ncard.xjtu.edu.cn`，鉴权全在 header：`Synjones-Auth: bearer <token>` + `synAccessSource: h5`。

1. `GET /berserker-base/redirect?type=login&loginFrom=h5&synAccessSource=h5` → CAS → 落到 `/plat/?ticket=…`
2. 用 ticket 换 token：`POST /berserker-auth/oauth/token`
   - form：`username=<ticket>&password=<ticket>&grant_type=password&scope=all&loginFrom=h5&logintype=sso&device_token=h5&synAccessSource=h5`
   - header：`Authorization: Basic bW9iaWxlX3NlcnZpY2VfcGxhdGZvcm06bW9iaWxlX3NlcnZpY2VfcGxhdGZvcm1fc2VjcmV0`
   - 响应：`{"access_token":…,"expires_in":7200}`
3. 用户信息：`GET /berserker-base/user?synAccessSource=h5` → `data.cardAccount|name|sno`
4. 余额：`GET /berserker-app/ykt/tsm/queryCard?synAccessSource=h5`
   `{"code":200,"data":{"card":[{"elec_accamt":334806,"unsettle_amount":"5000","barflag":0,"freezeflag":0,"expdate":"20301231","cardname":"校园卡（学生）"}]}}`
   金额单位是**分**；`unsettle_amount` 可能是字符串。
5. 流水：`GET /berserker-search/search/personal/turnover?size=30&current=1&timeFrom=YYYY-MM-DD&timeTo=YYYY-MM-DD&synAccessSource=h5`
   `data.records[]`：`jndatetimeStr`、`toMerchant`、`tranamt`（分）、`cardBalance`、`turnoverType`、`resume`、`typeFrom`（`"1"` 为收入）
6. 付款码：`GET /berserker-app/authCode/batchGetBarCodeGet?payacc=000&voucherType=1&synAccessSource=h5`
   → `data.barCodeVo.barcode[0]`（20 位数字）。Referer 用 `https://ncard.xjtu.edu.cn/plat/pay?lite=1&payacc=000&payid=0`

---

## 3. 图书馆座位（未实现）

Base：`http://rg.lib.xjtu.edu.cn:8086`（**http + 非标端口**，校外必须走 WebVPN）。鉴权只有 CAS Cookie。

| 端点 | 说明 |
|---|---|
| `GET /qspace?lang=zh&floor=<code>` | `{"sp":{区域码:名},"scount":{区域码:[总数,空位]}}` |
| `GET /qseat?sp=<区域码>` | `{"seat":{座位号:0 或非0}}`，**0 = 空位** |
| `GET /qseatuist?sp=<区域码>` | 座位矩形+状态，**2 = 空闲**、0 已预约、1 使用中、3 中途离开 |
| `GET /seat/?kid=<座位>&sp=<区域>` | 预约，成功则落到 `/my/` |
| `GET /my/` | 当前预约，`div.well`；`showConfirmModal('…','<action>','<ri>')` 里有动作 |
| `GET /my/?cancel=1&ri=<ri>` 等 | 取消 / 入馆签到 / 中途离开 / 中途返回 |
| `GET\|POST /modify` | 切校区（`rplace`），email/tel 必须回填 |

楼层码写死：兴庆 `east` → `xingqing2floor/3/4`；雁塔 `west` → `yanta1..4floor`；创新港 `inno` → `inno1floor/inno2floor`。

---

## 4. 空闲教室（未实现）

三档数据源：

- **CDN（免登录）**：`GET https://gh-release.xjtutoolbox.com/?file=static/empty_room/<yyyy-MM-dd>.json`
  → `{校区:{楼:{教室:{"status":[11 个 0/1],"size":N}}}}`（第三方镜像，不是学校接口）
- **LIVE**：`GET https://js.xjtu.edu.cn/server/classroomStatus/classroomStatusList?campusName=兴庆校区&dayTime=`
  header `TOKEN-AUTH: <JWT>`、`X-System: WEB`，token 由 `POST https://js.xjtu.edu.cn/server/cas/loginCas` 换
- **DIRECT（教务）**：`POST /jwapp/sys/kxjas/modules/kxjscx/cxkxjs.do`
  form `XXXQDM,JXLDM,KXRQ,KSJC,JSJC,pageSize=500,pageNumber=1` → `datas.cxkxjs.rows[]`（`JASMC/SKZWS/…`）

---

## 5. 通知聚合（未实现）

**没有 JSON 接口，全是 HTML 抓取**，`NotificationSource` 里 29 个源（教务处、研究生院、各学院、OA）。
每条目要抽：`title`（`a[title]` → `p`）、`link`（相对转绝对）、`date`（`span.time`/`em`/全文正则）、`tags`（`a > i`）。
OA 单独处理：`https://oa.xjtu.edu.cn/zxgg_index.jsp?strPageNo=N`，条目 `a.noa_list`，
`onclick="gotodetail('ID')"`，日期在 `td.timedate1` 的 `部门（2026-10-10）` 形式里。

公告（不需要登录）：`GET https://gitee.com/yeliqin666/xjtu-toolbox-android/raw/announce/bulletin.json`
（失败退 GitHub raw），字段 `id/title/body/level/url/startsAt/endsAt/minVersion/maxVersion/...`。

---

## 6. 成绩合并与 GPA（已实现 GPA）

安卓版是「jwapp 为基础 → 教务精确值替换 → 未评教报表补齐」三路合并：

- jwapp：`POST /api/biz/v410/score/termScore`，JSON `{"termCode":"*"}`，`Authorization: <token>`（**无 Bearer 前缀**）
- 精确值：`POST https://jwxt.xjtu.edu.cn/jwapp/sys/cjcx/modules/cjcx/xscjcx.do`
  form `querySetting=<SFYX 过滤>&pageSize=100&pageNumber=N`，`code` 是字符串 `"0"`
- GPA 4.3 制：`95+→4.3, 90→4.0, 85→3.7, 81→3.3, 78→3.0, 75→2.7, 72→2.3, 68→2.0, 64→1.7, 60→1.3`
- 加权是**按学分**；「通过 / 不通过」整条不计入；未通过且是「初修」的课也不计入

iOS 目前只用精确成绩这一路（`xscjcx`），已经能覆盖绝大多数情况。

---

## 7. 其它已知细节

- 课表周次位串 `SKZC`（`1` 表示那一周有课），学期起点 `XQKSRQ`，总周数 `ZZC`
- 作息时间有夏冬两套（5–9 月为夏季），iOS 端目前用统一的简易表，后续可补
- 调停补课走 `xsdkkc.do`，`TKLXDM` = 1 调课 / 2 停课 / 3 补课，按 `SQSJ` 升序合并
- 部分 jwxt 应用（`cjcx`、`kcbcx`、`wspjyyapp`）必须先 GET 其 `*default/index.do` 注册 session，否则返回 404
