import os
import json
import tkinter as tk
from tkinter import messagebox, scrolledtext
from datetime import datetime
import subprocess
import sys

BASE = os.path.dirname(os.path.abspath(__file__))

DATA = os.path.join(BASE, "students.json")
TIMER = os.path.join(BASE, "timer.pyw")

SESSION_SECONDS = 45 * 60


AGREEMENT_TEXT = """В компьютерной аудитории запрещается:

1. Есть за компьютером и оставлять крошки на клавиатуре.

2. Пить напитки рядом с компьютерами и другой техникой.

3. Курить, употреблять и приносить запрещённые вещества в аудиторию.

4. Грызть провода, клавиатуры, мыши и другие элементы компьютерной техники.

5. Пускать слюни, сопли и другие биологические жидкости на системные блоки, провода и периферию.

6. Ломать, пинать, бросать и иным образом проверять технику на прочность.

7. Трогать разъёмы, провода и внутренние компоненты компьютера без разрешения преподавателя.

8. Устанавливать посторонние программы и изменять настройки компьютера без разрешения преподавателя.

9. Отключать или подключать оборудование без разрешения преподавателя.

10. Использовать компьютер не по учебному назначению, если это мешает учебному процессу.

11. Кричать, мешать другим студентам и превращать компьютерную аудиторию в киберспортивный стадион.

12. Бить по клавиатуре так, будто она задолжала денег.

13. Использовать компьютер в качестве подставки для ног.

14. Наматывать провода на себя, соседа или системный блок.

15. Засовывать посторонние предметы в разъёмы компьютера.

16. Сидеть на столах, системных блоках и другой компьютерной технике.

17. Самостоятельно разбирать системный блок, монитор, клавиатуру или мышь.

18. Выдёргивать флешки, кабели и другие устройства без безопасного извлечения.

19. Подключать к компьютерам неизвестные устройства и накопители без разрешения преподавателя.
"""

def load():
    try:
        with open(DATA, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []


def save(data):
    records = load()
    records.append(data)

    with open(DATA, "w", encoding="utf-8") as f:
        json.dump(
            records,
            f,
            ensure_ascii=False,
            indent=2
        )


def show_agreement(parent):
    window = tk.Toplevel(parent)

    window.title("Пользовательское соглашение")
    window.geometry("900x700")
    window.configure(bg="#101318")

    # Окно соглашения поверх главного окна
    window.transient(parent)
    window.grab_set()

    # Временно убираем главное окно из режима "поверх всех"
    parent.attributes("-topmost", False)

    # Делаем соглашение поверх главного окна
    window.attributes("-topmost", True)

    def close_agreement():
        # Сначала закрываем окно соглашения
        window.grab_release()
        window.destroy()

        # После закрытия снова возвращаем главное окно поверх всех
        parent.attributes("-topmost", True)
        parent.lift()

    window.protocol(
        "WM_DELETE_WINDOW",
        close_agreement
    )

    title = tk.Label(
        window,
        text="Пользовательское соглашение",
        font=("Segoe UI", 22, "bold"),
        fg="white",
        bg="#101318"
    )
    title.pack(pady=(20, 10))

    text = scrolledtext.ScrolledText(
        window,
        font=("Segoe UI", 12),
        bg="#20252d",
        fg="white",
        insertbackground="white",
        wrap=tk.WORD,
        relief="flat"
    )

    text.pack(
        fill="both",
        expand=True,
        padx=30,
        pady=20
    )

    text.insert("1.0", AGREEMENT_TEXT)
    text.config(state="disabled")

    tk.Button(
        window,
        text="Закрыть",
        command=close_agreement,
        font=("Segoe UI", 13, "bold"),
        bg="#2d7ff9",
        fg="white",
        activebackground="#2469d1",
        activeforeground="white",
        relief="flat",
        padx=30,
        pady=10
    ).pack(pady=(0, 20))

    window.focus_force()

class App:

    def __init__(self, root):

        self.root = root

        root.title("Регистрация студента")
        root.configure(bg="#101318")

        root.attributes("-fullscreen", True)

        root.attributes("-topmost", True)

        root.protocol(
            "WM_DELETE_WINDOW",
            lambda: None
        )

        root.bind(
            "<Alt-F4>",
            lambda event: "break"
        )

        # Блокировка Escape
        root.bind(
            "<Escape>",
            lambda event: "break"
        )

        self.keep_topmost()

        self.create_ui()

    def keep_topmost(self):

        try:
            if self.root.winfo_exists():

                # Проверяем, есть ли открытое дочернее окно
                children = self.root.winfo_children()

                agreement_open = any(
                    isinstance(child, tk.Toplevel)
                    for child in children
                )

                # Если соглашение не открыто —
                # главное окно поверх всех
                if not agreement_open:
                    self.root.attributes("-topmost", True)

                self.root.after(
                    1000,
                    self.keep_topmost
                )

        except Exception:
            pass

    def create_field(self, parent, text):

        tk.Label(
            parent,
            text=text,
            font=("Segoe UI", 12),
            fg="white",
            bg="#101318"
        ).pack(
            fill="x",
            pady=(4, 5)
        )

        entry = tk.Entry(
            parent,
            font=("Segoe UI", 16),
            width=35,
            bg="#20252d",
            fg="white",
            insertbackground="white",
            relief="flat"
        )

        entry.pack(
            pady=(0, 12),
            ipady=9
        )

        return entry


    def create_ui(self):

        self.box = tk.Frame(
            self.root,
            bg="#101318"
        )

        self.box.place(
            relx=0.5,
            rely=0.5,
            anchor="center"
        )

        tk.Label(
            self.box,
            text="Регистрация студента",
            font=("Segoe UI", 30, "bold"),
            fg="white",
            bg="#101318"
        ).pack(
            pady=(0, 12)
        )

        tk.Label(
            self.box,
            text="Заполните данные для начала работы",
            font=("Segoe UI", 14),
            fg="#c7cbd1",
            bg="#101318"
        ).pack(
            pady=(0, 25)
        )

        # ФИО
        self.fio = self.create_field(
            self.box,
            "ФИО студента"
        )

        # Группа
        self.grp = self.create_field(
            self.box,
            "Группа"
        )

        tk.Label(
            self.box,
            text="Пара по счёту",
            font=("Segoe UI", 12),
            fg="white",
            bg="#101318"
        ).pack(
            fill="x"
        )

        self.pair = tk.Spinbox(
            self.box,
            from_=1,
            to=20,
            font=("Segoe UI", 16),
            width=8,
            justify="center"
        )

        self.pair.pack(
            pady=(5, 18),
            ipady=7
        )

        # Согласие
        self.agree = tk.BooleanVar(
            value=False
        )

        tk.Checkbutton(
            self.box,
            text="Я принимаю пользовательское соглашение",
            variable=self.agree,
            font=("Segoe UI", 12),
            fg="white",
            bg="#101318",
            activebackground="#101318",
            activeforeground="white",
            selectcolor="#20252d"
        ).pack(
            pady=(2, 10)
        )

        tk.Button(
            self.box,
            text="Прочитать пользовательское соглашение",
            command=lambda: show_agreement(self.root),
            font=("Segoe UI", 11),
            bg="#20252d",
            fg="white",
            activebackground="#303743",
            activeforeground="white",
            relief="flat",
            padx=20,
            pady=8
        ).pack(
            pady=(0, 20)
        )

        # Начать
        tk.Button(
            self.box,
            text="Начать работу",
            command=self.start,
            font=("Segoe UI", 15, "bold"),
            bg="#2d7ff9",
            fg="white",
            activebackground="#2469d1",
            activeforeground="white",
            relief="flat",
            padx=35,
            pady=12
        ).pack()

        self.fio.focus()


    def start(self):

        fio = self.fio.get().strip()
        group = self.grp.get().strip()

        try:
            pair = int(self.pair.get())
        except Exception:
            pair = 0

        # Проверки
        if not fio:
            messagebox.showwarning(
                "Ошибка",
                "Введите ФИО."
            )
            return

        if not group:
            messagebox.showwarning(
                "Ошибка",
                "Введите группу."
            )
            return

        if pair < 1:
            messagebox.showwarning(
                "Ошибка",
                "Введите номер пары."
            )
            return

        if not self.agree.get():
            messagebox.showwarning(
                "Ошибка",
                "Примите пользовательское соглашение."
            )
            return

        start_time = datetime.now()

        end_time = datetime.fromtimestamp(
            start_time.timestamp() + SESSION_SECONDS
        )

        save({
            "event": "session_started",
            "fio": fio,
            "group": group,
            "pair": pair,
            "agreement_accepted": True,
            "start_time": start_time.isoformat(
                timespec="seconds"
            ),
            "end_time": end_time.isoformat(
                timespec="seconds"
            )
        })

        if not os.path.exists(TIMER):

            messagebox.showerror(
                "Ошибка",
                "Файл timer.pyw не найден.\n\n"
                "Положите timer.pyw рядом с main.py."
            )

            return

        try:

            subprocess.Popen(
                [
                    sys.executable,
                    TIMER,
                    "--start-session"
                ],
                creationflags=subprocess.CREATE_NO_WINDOW
            )

        except Exception as e:

            messagebox.showerror(
                "Ошибка",
                f"Не удалось запустить таймер:\n\n{e}"
            )

            return

        self.root.destroy()

        os._exit(0)


if __name__ == "__main__":

    root = tk.Tk()

    App(root)

    root.mainloop()