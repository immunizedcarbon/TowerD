use eframe::{CreationContext, egui};

const BACKGROUND: egui::Color32 = egui::Color32::from_rgb(10, 13, 20);
const SURFACE: egui::Color32 = egui::Color32::from_rgb(24, 29, 40);
const NUMBER_KEY: egui::Color32 = egui::Color32::from_rgb(34, 40, 54);
const UTILITY_KEY: egui::Color32 = egui::Color32::from_rgb(49, 57, 75);
const OPERATOR_KEY: egui::Color32 = egui::Color32::from_rgb(77, 91, 220);
const EQUALS_KEY: egui::Color32 = egui::Color32::from_rgb(41, 181, 154);
const CLEAR_KEY: egui::Color32 = egui::Color32::from_rgb(128, 55, 72);
const PRIMARY_TEXT: egui::Color32 = egui::Color32::from_rgb(244, 247, 255);
const SECONDARY_TEXT: egui::Color32 = egui::Color32::from_rgb(156, 166, 189);

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
fn android_main(app: winit::platform::android::activity::AndroidApp) {
    android_logger::init_once(
        android_logger::Config::default().with_max_level(log::LevelFilter::Info),
    );

    let options = eframe::NativeOptions {
        android_app: Some(app),
        ..Default::default()
    };

    eframe::run_native(
        "Rust Calculator",
        options,
        Box::new(|cc| Ok(Box::new(CalculatorApp::new(cc)))),
    )
    .expect("failed to start Rust Calculator");
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Operator {
    Add,
    Subtract,
    Multiply,
    Divide,
}

impl Operator {
    fn symbol(self) -> &'static str {
        match self {
            Self::Add => "+",
            Self::Subtract => "−",
            Self::Multiply => "×",
            Self::Divide => "÷",
        }
    }
}

struct CalculatorApp {
    display: String,
    expression: String,
    accumulator: Option<f64>,
    pending_operator: Option<Operator>,
    replace_display: bool,
    has_error: bool,
}

impl CalculatorApp {
    fn new(cc: &CreationContext<'_>) -> Self {
        let mut visuals = egui::Visuals::dark();
        visuals.panel_fill = BACKGROUND;
        visuals.window_fill = BACKGROUND;
        visuals.extreme_bg_color = SURFACE;
        visuals.override_text_color = Some(PRIMARY_TEXT);
        cc.egui_ctx.set_visuals(visuals);

        let mut style = (*cc.egui_ctx.style()).clone();
        style.spacing.item_spacing = egui::vec2(12.0, 12.0);
        style.spacing.button_padding = egui::vec2(14.0, 14.0);
        cc.egui_ctx.set_style(style);

        Self {
            display: "0".to_owned(),
            expression: String::new(),
            accumulator: None,
            pending_operator: None,
            replace_display: false,
            has_error: false,
        }
    }

    fn clear(&mut self) {
        self.display.clear();
        self.display.push('0');
        self.expression.clear();
        self.accumulator = None;
        self.pending_operator = None;
        self.replace_display = false;
        self.has_error = false;
    }

    fn input_digit(&mut self, digit: char) {
        if self.has_error {
            self.clear();
        }

        if self.replace_display {
            self.display.clear();
            self.expression.clear();
            self.replace_display = false;
        }

        if self.display == "0" {
            self.display.clear();
        }

        if self.display.len() < 18 {
            self.display.push(digit);
        }
    }

    fn input_decimal(&mut self) {
        if self.has_error {
            self.clear();
        }

        if self.replace_display {
            self.display.clear();
            self.display.push('0');
            self.expression.clear();
            self.replace_display = false;
        }

        if !self.display.contains('.') {
            self.display.push('.');
        }
    }

    fn toggle_sign(&mut self) {
        if self.has_error || self.display == "0" {
            return;
        }

        if self.display.starts_with('-') {
            self.display.remove(0);
        } else {
            self.display.insert(0, '-');
        }
    }

    fn percent(&mut self) {
        let Some(value) = self.current_value() else {
            self.set_error();
            return;
        };

        let source = self.display.clone();
        self.display = format_value(value / 100.0);
        self.expression = format!("{source}%");
        self.replace_display = true;
    }

    fn backspace(&mut self) {
        if self.has_error || self.replace_display {
            return;
        }

        self.display.pop();
        if self.display.is_empty() || self.display == "-" {
            self.display.clear();
            self.display.push('0');
        }
    }

    fn choose_operator(&mut self, operator: Operator) {
        if self.has_error {
            return;
        }

        let Some(current) = self.current_value() else {
            self.set_error();
            return;
        };

        let next_accumulator = if let (Some(lhs), Some(previous_operator)) =
            (self.accumulator, self.pending_operator)
        {
            if self.replace_display {
                lhs
            } else {
                match calculate(lhs, current, previous_operator) {
                    Ok(value) => value,
                    Err(()) => {
                        self.set_error();
                        return;
                    }
                }
            }
        } else {
            current
        };

        self.display = format_value(next_accumulator);
        self.accumulator = Some(next_accumulator);
        self.pending_operator = Some(operator);
        self.expression = format!("{} {}", self.display, operator.symbol());
        self.replace_display = true;
    }

    fn equals(&mut self) {
        if self.has_error {
            return;
        }

        let (Some(lhs), Some(operator), Some(rhs)) = (
            self.accumulator,
            self.pending_operator,
            self.current_value(),
        ) else {
            self.replace_display = true;
            return;
        };

        match calculate(lhs, rhs, operator) {
            Ok(result) => {
                self.expression = format!(
                    "{} {} {} =",
                    format_value(lhs),
                    operator.symbol(),
                    format_value(rhs)
                );
                self.display = format_value(result);
                self.accumulator = None;
                self.pending_operator = None;
                self.replace_display = true;
            }
            Err(()) => self.set_error(),
        }
    }

    fn current_value(&self) -> Option<f64> {
        self.display.parse::<f64>().ok()
    }

    fn set_error(&mut self) {
        self.display.clear();
        self.display.push_str("Error");
        self.expression.clear();
        self.accumulator = None;
        self.pending_operator = None;
        self.replace_display = true;
        self.has_error = true;
    }

    fn draw_header(&self, ui: &mut egui::Ui) {
        ui.horizontal(|ui| {
            ui.vertical(|ui| {
                ui.label(
                    egui::RichText::new("Rust Calculator")
                        .size(22.0)
                        .strong()
                        .color(PRIMARY_TEXT),
                );
                ui.label(
                    egui::RichText::new("Android 17 · Native Rust")
                        .size(13.0)
                        .color(SECONDARY_TEXT),
                );
            });
        });
    }

    fn draw_display(&self, ui: &mut egui::Ui) {
        egui::Frame::new()
            .fill(SURFACE)
            .corner_radius(egui::CornerRadius::same(24))
            .show(ui, |ui| {
                ui.set_min_width(ui.available_width());
                ui.add_space(18.0);

                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let text = if self.expression.is_empty() {
                        " "
                    } else {
                        self.expression.as_str()
                    };
                    ui.label(
                        egui::RichText::new(text)
                            .size(16.0)
                            .color(SECONDARY_TEXT),
                    );
                });

                ui.add_space(8.0);

                let result_size = match self.display.len() {
                    0..=8 => 52.0,
                    9..=12 => 42.0,
                    13..=16 => 34.0,
                    _ => 28.0,
                };

                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.label(
                        egui::RichText::new(&self.display)
                            .size(result_size)
                            .strong()
                            .color(PRIMARY_TEXT),
                    );
                });

                ui.add_space(18.0);
            });
    }

    fn calculator_button(
        ui: &mut egui::Ui,
        label: &str,
        fill: egui::Color32,
        width: f32,
        height: f32,
    ) -> bool {
        ui.add_sized(
            [width, height],
            egui::Button::new(
                egui::RichText::new(label)
                    .size(if label.len() > 1 { 21.0 } else { 25.0 })
                    .strong()
                    .color(PRIMARY_TEXT),
            )
            .fill(fill)
            .corner_radius(egui::CornerRadius::same(20)),
        )
        .clicked()
    }

    fn draw_keypad(&mut self, ui: &mut egui::Ui) {
        let gap = 12.0;
        let key_width = ((ui.available_width() - gap * 3.0) / 4.0).max(54.0);
        let available_height = ui.available_height().max(320.0);
        let key_height = ((available_height - gap * 4.0) / 5.0).clamp(58.0, 82.0);

        egui::Grid::new("calculator_keypad")
            .num_columns(4)
            .spacing([gap, gap])
            .show(ui, |ui| {
                if Self::calculator_button(ui, "AC", CLEAR_KEY, key_width, key_height) {
                    self.clear();
                }
                if Self::calculator_button(ui, "±", UTILITY_KEY, key_width, key_height) {
                    self.toggle_sign();
                }
                if Self::calculator_button(ui, "%", UTILITY_KEY, key_width, key_height) {
                    self.percent();
                }
                if Self::calculator_button(ui, "⌫", UTILITY_KEY, key_width, key_height) {
                    self.backspace();
                }
                ui.end_row();

                for digit in ['7', '8', '9'] {
                    if Self::calculator_button(
                        ui,
                        &digit.to_string(),
                        NUMBER_KEY,
                        key_width,
                        key_height,
                    ) {
                        self.input_digit(digit);
                    }
                }
                if Self::calculator_button(ui, "÷", OPERATOR_KEY, key_width, key_height) {
                    self.choose_operator(Operator::Divide);
                }
                ui.end_row();

                for digit in ['4', '5', '6'] {
                    if Self::calculator_button(
                        ui,
                        &digit.to_string(),
                        NUMBER_KEY,
                        key_width,
                        key_height,
                    ) {
                        self.input_digit(digit);
                    }
                }
                if Self::calculator_button(ui, "×", OPERATOR_KEY, key_width, key_height) {
                    self.choose_operator(Operator::Multiply);
                }
                ui.end_row();

                for digit in ['1', '2', '3'] {
                    if Self::calculator_button(
                        ui,
                        &digit.to_string(),
                        NUMBER_KEY,
                        key_width,
                        key_height,
                    ) {
                        self.input_digit(digit);
                    }
                }
                if Self::calculator_button(ui, "−", OPERATOR_KEY, key_width, key_height) {
                    self.choose_operator(Operator::Subtract);
                }
                ui.end_row();

                if Self::calculator_button(ui, "0", NUMBER_KEY, key_width, key_height) {
                    self.input_digit('0');
                }
                if Self::calculator_button(ui, ".", NUMBER_KEY, key_width, key_height) {
                    self.input_decimal();
                }
                if Self::calculator_button(ui, "=", EQUALS_KEY, key_width, key_height) {
                    self.equals();
                }
                if Self::calculator_button(ui, "+", OPERATOR_KEY, key_width, key_height) {
                    self.choose_operator(Operator::Add);
                }
                ui.end_row();
            });
    }
}

impl eframe::App for CalculatorApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default().show(ui, |ui| {
            ui.add_space(18.0);
            ui.horizontal(|ui| {
                ui.add_space(18.0);
                ui.vertical(|ui| {
                    ui.set_width((ui.available_width() - 18.0).max(240.0));
                    self.draw_header(ui);
                    ui.add_space(18.0);
                    self.draw_display(ui);
                    ui.add_space(18.0);
                    self.draw_keypad(ui);
                    ui.add_space(16.0);
                });
            });
        });
    }

    fn clear_color(&self, _visuals: &egui::Visuals) -> [f32; 4] {
        BACKGROUND.to_normalized_gamma_f32()
    }
}

fn calculate(lhs: f64, rhs: f64, operator: Operator) -> Result<f64, ()> {
    let result = match operator {
        Operator::Add => lhs + rhs,
        Operator::Subtract => lhs - rhs,
        Operator::Multiply => lhs * rhs,
        Operator::Divide => {
            if rhs.abs() <= f64::EPSILON {
                return Err(());
            }
            lhs / rhs
        }
    };

    result.is_finite().then_some(result).ok_or(())
}

fn format_value(value: f64) -> String {
    let value = if value.abs() < 1.0e-12 { 0.0 } else { value };
    let absolute = value.abs();

    if absolute >= 1.0e12 || (absolute > 0.0 && absolute < 1.0e-8) {
        return format!("{value:.8e}");
    }

    let mut text = format!("{value:.10}");
    while text.contains('.') && text.ends_with('0') {
        text.pop();
    }
    if text.ends_with('.') {
        text.pop();
    }
    text
}
