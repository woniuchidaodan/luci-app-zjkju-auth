package main

import (
	"bufio"
	"flag"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"
)

const (
	Timeout = 15 * time.Second
)

type LoginParams struct {
	Username        string
	Password        string
	ServiceType     string
	OperatorCode    string
	PasswordEncrypt string
}

func main() {
	username := flag.String("u", "", "认证用户名")
	password := flag.String("p", "", "认证密码")
	serviceType := flag.String("s", "default", "服务类型: default(学生) / Teacher(教师)")
	operatorCode := flag.String("c", "", "运营商代码（可选）")
	persistent := flag.Bool("e", false, "启用持久化登录模式")
	manualURL := flag.String("m", "", "手动指定完整认证页面地址")
	help := flag.Bool("h", false, "显示帮助信息")

	flag.Parse()

	if *help || (*username == "" && *password == "") {
		fmt.Println("锐捷校园网认证客户端")
		fmt.Println("")
		fmt.Println("用法: ruijie [选项]")
		fmt.Println("")
		fmt.Println("选项:")
		fmt.Println("  -u string    认证用户名")
		fmt.Println("  -p string    认证密码")
		fmt.Println("  -s string    服务类型: default(学生) / Teacher(教师)")
		fmt.Println("  -c string    运营商代码（可选）")
		fmt.Println("  -m string    完整认证页面地址")
		fmt.Println("  -e           启用持久化登录模式")
		fmt.Println("  -h           显示此帮助信息")
		fmt.Println("")
		fmt.Println("示例:")
		fmt.Println("  ruijie -u 学号 -p 密码 -m \"http://172.17.211.2/eportal/index.jsp?wlanuserip=...\"")
		os.Exit(0)
	}

	params := LoginParams{
		Username:        *username,
		Password:        *password,
		ServiceType:     *serviceType,
		OperatorCode:    *operatorCode,
		PasswordEncrypt: "false",
	}

	fmt.Printf("锐捷认证客户端启动\n")
	fmt.Printf("用户名: %s\n", params.Username)
	fmt.Printf("身份类型: %s\n", params.ServiceType)

	var loginURL string
	if *manualURL != "" {
		loginURL = *manualURL
		fmt.Printf("使用手动指定的认证地址\n")
	} else {
		fmt.Println("尝试自动获取认证地址...")
		loginURL = getLoginURL()
		if loginURL == "" {
			fmt.Println("自动获取失败，请输入完整认证地址")
			fmt.Print("请输入认证地址: ")
			reader := bufio.NewReader(os.Stdin)
			input, _ := reader.ReadString('\n')
			loginURL = strings.TrimSpace(input)
			if loginURL == "" {
				fmt.Println("未输入认证地址，程序退出")
				return
			}
		}
	}

	fmt.Printf("认证地址: %s\n", loginURL)

	// 如果URL是redirectortosuccess.jsp，先获取真实的index.jsp地址
	if strings.Contains(loginURL, "redirectortosuccess.jsp") {
		fmt.Println("🔍 检测到重定向页面，获取真实认证地址...")
		realURL := fetchRealLoginURL(loginURL)
		if realURL != "" {
			loginURL = realURL
			fmt.Printf("真实认证地址: %s\n", loginURL)
		} else {
			fmt.Println("无法获取真实认证地址，请使用 -m 参数手动指定")
			return
		}
	}

	// 从URL中提取queryString
	queryString := extractQueryStringFromURL(loginURL)
	if queryString == "" {
		fmt.Println("未能从URL中提取queryString")
		fmt.Println("请确保URL包含 wlanuserip 等参数")
	} else {
		fmt.Printf("提取到queryString (长度: %d)\n", len(queryString))
	}

	// 构建POST数据
	formData := url.Values{}
	formData.Set("userId", params.Username)
	formData.Set("password", params.Password)
	formData.Set("service", params.ServiceType)
	formData.Set("queryString", queryString)
	formData.Set("operatorPwd", params.OperatorCode)
	formData.Set("operatorUserId", params.OperatorCode)
	formData.Set("validcode", "")
	formData.Set("passwordEncrypt", params.PasswordEncrypt)

	if *persistent {
		fmt.Println("持久化模式已开启，每10秒检测一次")
		for {
			if !checkNetwork() {
				fmt.Println("网络已断开，尝试重新认证...")
				doLogin(loginURL, formData)
			} else {
				fmt.Println("网络连接正常")
			}
			time.Sleep(10 * time.Second)
		}
	} else {
		if !checkNetwork() {
			doLogin(loginURL, formData)
		} else {
			fmt.Println("已联网，无需认证")
		}
	}
}

// 执行登录认证
func doLogin(loginURL string, formData url.Values) {
	fmt.Println("正在尝试认证...")

	// 构建认证接口URL
	targetURL := buildAuthURL(loginURL)
	fmt.Printf("认证请求URL: %s\n", targetURL)

	fmt.Printf("发送POST数据...\n")

	client := &http.Client{Timeout: Timeout}
	loginResp, err := client.Post(targetURL, "application/x-www-form-urlencoded", strings.NewReader(formData.Encode()))
	if err != nil {
		fmt.Printf("认证请求失败: %v\n", err)
		return
	}
	defer loginResp.Body.Close()

	body, err := ioutil.ReadAll(loginResp.Body)
	if err != nil {
		fmt.Printf("读取响应失败: %v\n", err)
		return
	}

	bodyStr := string(body)
	fmt.Printf("响应状态: %d\n", loginResp.StatusCode)

	if len(bodyStr) > 0 {
		fmt.Printf("响应内容: %s\n", bodyStr[:min(500, len(bodyStr))])
	}

	// 判断认证结果
	if loginResp.StatusCode == 200 {
		if strings.Contains(bodyStr, `"result":"success"`) ||
			strings.Contains(bodyStr, "登录成功") ||
			strings.Contains(bodyStr, "认证成功") {
			fmt.Println("认证成功！")
		} else if strings.Contains(bodyStr, `"result":"fail"`) ||
			strings.Contains(bodyStr, "失败") {
			msg := extractErrorMessage(bodyStr)
			fmt.Printf("认证失败: %s\n", msg)
		} else if strings.Contains(bodyStr, "上网") || strings.Contains(bodyStr, "已登录") {
			fmt.Println("认证成功！")
		} else {
			fmt.Println("认证请求已提交，请检查是否能正常上网")
			fmt.Println("如果无法上网，请检查:")
			fmt.Println("  1. queryString是否完整")
			fmt.Println("  2. 服务类型是否正确 (default/Teacher)")
			fmt.Println("  3. 用户名密码是否正确")
		}
	} else {
		fmt.Printf("认证请求失败 (HTTP %d)\n", loginResp.StatusCode)
	}
}

// 构建认证接口URL - 修正路径
func buildAuthURL(loginURL string) string {
	// 提取基础路径
	var baseURL string
	
	// 去掉查询参数
	if idx := strings.Index(loginURL, "?"); idx != -1 {
		baseURL = loginURL[:idx]
	} else {
		baseURL = loginURL
	}

	// 去掉末尾的斜杠
	baseURL = strings.TrimSuffix(baseURL, "/")

	// 提取eportal目录路径
	var eportalPath string
	if idx := strings.Index(baseURL, "/eportal/"); idx != -1 {
		eportalPath = baseURL[:idx+len("/eportal/")]
	} else if idx := strings.Index(baseURL, "/eportal"); idx != -1 {
		eportalPath = baseURL[:idx+len("/eportal")] + "/"
	} else {
		// 没有eportal目录，使用父目录
		lastSlash := strings.LastIndex(baseURL, "/")
		if lastSlash != -1 {
			eportalPath = baseURL[:lastSlash+1]
		} else {
			eportalPath = baseURL + "/"
		}
	}

	// 构建正确的认证接口URL
	targetURL := eportalPath + "InterFace.do?method=login"
	return targetURL
}

// 获取真实的认证地址（从redirectortosuccess.jsp响应中提取）
func fetchRealLoginURL(redirectURL string) string {
	client := &http.Client{Timeout: Timeout}
	resp, err := client.Get(redirectURL)
	if err != nil {
		fmt.Printf("获取重定向页面失败: %v\n", err)
		return ""
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("读取重定向页面失败: %v\n", err)
		return ""
	}

	bodyStr := string(body)
	
	// 从location.href中提取
	re := regexp.MustCompile(`location\.href\s*=\s*['"]([^'"]+)['"]`)
	matches := re.FindStringSubmatch(bodyStr)
	if len(matches) > 1 {
		return matches[1]
	}
	
	// 匹配 window.location='...'
	re2 := regexp.MustCompile(`window\.location\s*=\s*['"]([^'"]+)['"]`)
	matches2 := re2.FindStringSubmatch(bodyStr)
	if len(matches2) > 1 {
		return matches2[1]
	}
	
	// 匹配 top.self.location.href='...'
	re3 := regexp.MustCompile(`top\.self\.location\.href\s*=\s*['"]([^'"]+)['"]`)
	matches3 := re3.FindStringSubmatch(bodyStr)
	if len(matches3) > 1 {
		return matches3[1]
	}
	
	return ""
}

// 检测网络状态
func checkNetwork() bool {
	client := &http.Client{
		Timeout: Timeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}

	checkURLs := []string{"http://www.baidu.com", "http://www.qq.com", "http://www.163.com"}

	for _, url := range checkURLs {
		resp, err := client.Get(url)
		if err != nil {
			continue
		}
		defer resp.Body.Close()

		if resp.StatusCode == 204 {
			return true
		}
		if resp.StatusCode == 302 || resp.StatusCode == 301 {
			return false
		}
		if resp.StatusCode == 200 {
			body, _ := ioutil.ReadAll(resp.Body)
			bodyStr := string(body)
			if strings.Contains(bodyStr, "eportal") || strings.Contains(bodyStr, "认证") {
				return false
			}
			return true
		}
	}
	return false
}

// 获取认证页面地址
func getLoginURL() string {
	client := &http.Client{
		Timeout: Timeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}

	gatewayIPs := []string{
		"http://172.17.211.2",
		"http://10.0.0.1",
		"http://192.168.1.1",
	}

	for _, ip := range gatewayIPs {
		resp, err := client.Get(ip)
		if err != nil {
			continue
		}
		defer resp.Body.Close()

		if resp.StatusCode == 302 || resp.StatusCode == 301 {
			loginURL := resp.Header.Get("Location")
			if loginURL != "" && strings.Contains(loginURL, "eportal") {
				return loginURL
			}
		}

		if resp.StatusCode == 200 {
			body, _ := ioutil.ReadAll(resp.Body)
			bodyStr := string(body)
			if strings.Contains(bodyStr, "eportal") {
				re := regexp.MustCompile(`<form[^>]*action=["']([^"']+)["']`)
				matches := re.FindStringSubmatch(bodyStr)
				if len(matches) > 1 {
					actionURL := matches[1]
					if strings.HasPrefix(actionURL, "http") {
						return actionURL
					}
					return ip + actionURL
				}
				return ip + "/eportal/index.jsp"
			}
		}
	}
	return ""
}

// 从URL中提取queryString
func extractQueryStringFromURL(loginURL string) string {
	u, err := url.Parse(loginURL)
	if err == nil {
		q := u.Query()
		if qs := q.Get("queryString"); qs != "" {
			return qs
		}
		if q.Get("wlanuserip") != "" {
			params := url.Values{}
			for key, values := range q {
				if key != "queryString" {
					for _, value := range values {
						params.Add(key, value)
					}
				}
			}
			return params.Encode()
		}
	}

	idx := strings.Index(loginURL, "?")
	if idx != -1 {
		queryPart := loginURL[idx+1:]
		if !strings.Contains(queryPart, "queryString=") {
			return queryPart
		}
	}

	re := regexp.MustCompile(`queryString=([^&]+)`)
	matches := re.FindStringSubmatch(loginURL)
	if len(matches) > 1 {
		return matches[1]
	}

	return ""
}

// 提取错误信息
func extractErrorMessage(body string) string {
	re := regexp.MustCompile(`"message":"([^"]+)"`)
	matches := re.FindStringSubmatch(body)
	if len(matches) > 1 {
		return matches[1]
	}
	re2 := regexp.MustCompile(`<p[^>]*>([^<]+)</p>`)
	matches2 := re2.FindStringSubmatch(body)
	if len(matches2) > 1 {
		return matches2[1]
	}
	return "未知错误"
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
