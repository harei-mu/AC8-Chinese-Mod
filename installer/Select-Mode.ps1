function Select-InstallMode {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object Windows.Forms.Form
    $form.Text = 'ACE COMBAT 8 简体汉化'
    $form.ClientSize = New-Object Drawing.Size(510, 280)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $label = New-Object Windows.Forms.Label
    $label.SetBounds(24, 20, 460, 44)
    $label.Text = '选择汉化内容。安装后可直接从 Steam 启动单机游戏。'
    $label.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
    $form.Controls.Add($label)
    $choices = @()
    foreach ($item in @(@('Both','全部汉化：界面和 HUD'), @('UI','界面汉化：菜单、设置、资料和结算'), @('HUD','HUD 汉化：仪表、雷达和目标名称'))) {
        $radio = New-Object Windows.Forms.RadioButton
        $radio.SetBounds(26, (74 + $choices.Count * 36), 460, 28)
        $radio.Text = $item[1]; $radio.Tag = $item[0]
        $radio.Checked = ($choices.Count -eq 0)
        $form.Controls.Add($radio); $choices += $radio
    }
    $note = New-Object Windows.Forms.Label
    $note.SetBounds(24, 186, 460, 42)
    $note.Text = '安装会正常退出并重新打开 Steam。卸载会恢复原启动设置。'
    $form.Controls.Add($note)
    $ok = New-Object Windows.Forms.Button
    $ok.SetBounds(368, 235, 110, 30); $ok.Text = '安装汉化'
    $ok.DialogResult = [Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $ok; $form.Controls.Add($ok)
    if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw '已取消安装。' }
    $result = ($choices | Where-Object Checked).Tag
    $form.Dispose(); return $result
}
