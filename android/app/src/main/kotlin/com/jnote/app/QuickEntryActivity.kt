package com.jnote.app

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.view.WindowInsets
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.ImageButton
import android.widget.Toast

/**
 * The small input card the widget opens over the home screen. It is plain
 * Android (no Flutter engine), so it opens instantly, and it lives in its own
 * task that is excluded from recents, so finishing returns to the home screen.
 */
class QuickEntryActivity : Activity() {
    private lateinit var input: EditText
    private lateinit var save: ImageButton

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_quick_entry)
        val root = findViewById<View>(R.id.root)
        input = findViewById(R.id.input)
        save = findViewById(R.id.save)

        if (Build.VERSION.SDK_INT >= 30) {
            // Edge-to-edge (enforced from Android 15): keep the card above the keyboard and nav bar ourselves.
            window.setDecorFitsSystemWindows(false)
            root.setOnApplyWindowInsetsListener { v, insets ->
                val bars = insets.getInsets(WindowInsets.Type.ime() or WindowInsets.Type.systemBars())
                v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
                WindowInsets.CONSUMED
            }
        }
        // Tapping outside closes only an empty card, so typed text is never lost by accident.
        root.setOnClickListener { if (input.text.isBlank()) finish() }
        save.setOnClickListener { saveNote() }
        input.addTextChangedListener(object : TextWatcher {
            override fun afterTextChanged(s: Editable) = updateSave()
            override fun beforeTextChanged(s: CharSequence, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence, start: Int, before: Int, count: Int) = Unit
        })
        // Text left unsaved last time (Home, a call, the screen going off) comes back.
        drafts().getString(DRAFT, null)?.let {
            input.setText(it)
            input.setSelection(it.length)
        }
        updateSave()
        input.requestFocus()
    }

    override fun onStop() {
        super.onStop()
        val text = input.text.toString()
        drafts().edit().apply { if (text.isBlank()) remove(DRAFT) else putString(DRAFT, text) }.apply()
    }

    private fun drafts() = getSharedPreferences("quick_entry", MODE_PRIVATE)

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) getSystemService(InputMethodManager::class.java).showSoftInput(input, 0)
    }

    private fun updateSave() {
        val enabled = input.text.isNotBlank()
        save.isEnabled = enabled
        save.alpha = if (enabled) 1f else 0.4f
    }

    private fun saveNote() {
        // "- " or "* " at a line start is stored as the app's bullet.
        val text = input.text.toString().trim().lines().joinToString("\n") { it.replace(BULLET, "• ") }
        if (text.isBlank()) return
        try {
            NoteStore.with(this) { it.insert(text) } // synchronous: the note is on disk before the card closes
        } catch (e: Exception) {
            Toast.makeText(this, R.string.save_failed, Toast.LENGTH_LONG).show()
            return
        }
        Toast.makeText(applicationContext, R.string.saved, Toast.LENGTH_SHORT).show()
        input.text.clear() // saved, so no draft is kept
        finish()
    }

    private companion object {
        val BULLET = Regex("^[-*] ")
        const val DRAFT = "draft"
    }
}
