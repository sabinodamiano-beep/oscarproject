import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../clientes/domain/entities/cliente.dart';
import '../../../clientes/presentation/providers/cliente_provider.dart';
import '../../../items/domain/entities/item.dart';
import '../../../items/presentation/providers/item_provider.dart';
import '../providers/pedido_provider.dart';
import '../../../../core/sync/connection_monitor.dart';

class PedidoCrearScreen extends StatefulWidget {
  const PedidoCrearScreen({super.key});

  @override
  State<PedidoCrearScreen> createState() => _PedidoCrearScreenState();
}

class _PedidoCrearScreenState extends State<PedidoCrearScreen> {
  final _obsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _obsController.text = context.read<PedidosProvider>().observaciones;
  }

  @override
  void dispose() {
    _obsController.dispose();
    super.dispose();
  }

  Future<void> _seleccionarCliente() async {
    final cliente = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(builder: (_) => const _SeleccionarClienteScreen()),
    );
    if (cliente != null && mounted) {
      context.read<PedidosProvider>().seleccionarCliente(cliente);
    }
  }

  Future<void> _agregarProducto() async {
    final item = await Navigator.push<Item>(
      context,
      MaterialPageRoute(builder: (_) => const _SeleccionarProductoScreen()),
    );
    if (item != null && mounted) {
      context.read<PedidosProvider>().agregarItem(item);
    }
  }

  Future<void> _enviar() async {
    final provider = context.read<PedidosProvider>();
    provider.setObservaciones(_obsController.text);
    final editando = provider.enModoEdicion;
    final sinConexion = !ConnectionMonitor.instance.intentarRemoto;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(provider.editandoUid != null
            ? 'Guardar cambios en #${provider.editandoUid}'
            : provider.enModoEdicionLocal
                ? 'Guardar pedido'
                : 'Confirmar pedido'),
        content: Text(
          'Cliente: ${provider.clienteSeleccionado?.nombreCompleto}\n'
          'Productos: ${provider.carrito.length}\n'
          'Total: \$${provider.totalCarrito.toStringAsFixed(2)}'
          '${sinConexion && provider.editandoUid == null ? '\n\nSin conexión: el pedido se guardará en el teléfono y se enviará al recuperar señal. Los precios son los de la última sincronización.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
            child: Text(editando ? 'Guardar' : 'Enviar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final uid = await provider.enviarPedido();
    if (!mounted) return;
    if (uid != null) {
      Navigator.pop(context, provider.mensajeUltimoEnvio ?? uid);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorEnviar ?? 'Error al enviar'), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<bool> _confirmarSalida() async {
    final provider = context.read<PedidosProvider>();
    if (provider.carrito.isEmpty && provider.clienteSeleccionado == null) return true;
    final editando = provider.enModoEdicion;
    final salir = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(editando ? '¿Descartar cambios?' : '¿Descartar pedido?'),
        content: Text(editando ? 'El pedido quedará como estaba.' : 'Se perderán los productos agregados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir editando')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (salir == true) provider.limpiarCarrito();
    return salir == true;
  }

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _confirmarSalida,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(context.watch<PedidosProvider>().tituloCarrito),
        ),
        body: Consumer<PedidosProvider>(
          builder: (context, provider, _) {
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      _SeccionTitulo('Cliente'),
                      _ClienteSelector(
                        cliente: provider.clienteSeleccionado,
                        onTap: provider.enModoEdicion ? null : _seleccionarCliente,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _SeccionTitulo('Productos (${provider.carrito.length})'),
                          TextButton.icon(
                            onPressed: _agregarProducto,
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text('Agregar'),
                          ),
                        ],
                      ),
                      if (provider.carrito.isEmpty)
                        _CajaVacia(onTap: _agregarProducto)
                      else
                        ...provider.carrito.map((l) => _LineaCard(linea: l)),
                      const SizedBox(height: 20),
                      _SeccionTitulo('Observaciones'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _obsController,
                        maxLines: 3,
                        maxLength: 600,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(hintText: 'Opcional', counterText: ''),
                        onChanged: provider.setObservaciones,
                      ),
                    ],
                  ),
                ),
                _BarraTotal(
                  total: provider.totalCarrito,
                  habilitado: provider.carritoListo && !provider.estaEnviando,
                  enviando: provider.estaEnviando,
                  editando: provider.enModoEdicion,
                  onEnviar: _enviar,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ==================== WIDGETS DE LA PANTALLA ====================

class _SeccionTitulo extends StatelessWidget {
  final String texto;
  const _SeccionTitulo(this.texto);
  @override
  Widget build(BuildContext context) => Text(
        texto,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
      );
}

class _ClienteSelector extends StatelessWidget {
  final Cliente? cliente;
  final VoidCallback? onTap;
  const _ClienteSelector({required this.cliente, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cliente == null ? AppTheme.primary : AppTheme.divider, width: cliente == null ? 1.5 : 0.5),
        ),
        child: Row(
          children: [
            Icon(cliente == null ? Icons.person_search_rounded : Icons.person_rounded, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: cliente == null
                  ? const Text('Seleccionar cliente', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cliente!.nombreCompleto,
                            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                        if (cliente!.cedula.isNotEmpty)
                          Text(cliente!.cedulaCompleta, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _CajaVacia extends StatelessWidget {
  final VoidCallback onTap;
  const _CajaVacia({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider, width: 0.5),
        ),
        child: const Column(
          children: [
            Icon(Icons.inventory_2_outlined, color: AppTheme.textSecondary, size: 36),
            SizedBox(height: 8),
            Text('Toca para agregar productos', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de una línea con contadores de cajas y botellas
class _LineaCard extends StatelessWidget {
  final LineaCarrito linea;
  const _LineaCard({required this.linea});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<PedidosProvider>();
    final item = linea.item;
    final etiquetaCaja = item.cantunidad > 1 ? 'Cajas' : 'Cant.';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.desitems,
                        style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (item.activo != '1')
                      const Text('Producto inactivo: quítelo para poder guardar',
                          style: TextStyle(color: AppTheme.error, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                      '${_descripcionProducto(item)} · \$${linea.precioUnit.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => provider.quitarLinea(item.coditems),
                icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error, size: 22),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (item.tieneVariosPrecios) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: item.preciosDisponibles.entries.map((e) {
                  final sel = linea.precioNivel == e.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        '${Item.nombresNivel[e.key]} \$${e.value.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                            color: sel ? Colors.white : AppTheme.textSecondary),
                      ),
                      selected: sel,
                      showCheckmark: false,
                      selectedColor: AppTheme.accent,
                      backgroundColor: AppTheme.surface,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) =>
                          provider.actualizarLinea(item.coditems, precioNivel: e.key),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Contador(
                  etiqueta: etiquetaCaja,
                  valor: linea.cajas,
                  onChanged: (v) => provider.actualizarLinea(item.coditems, cajas: v),
                ),
              ),
              if (item.permiteBotellas) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _Contador(
                    etiqueta: 'Botellas',
                    valor: linea.botellas,
                    max: item.cantunidad - 1,
                    onChanged: (v) => provider.actualizarLinea(item.coditems, botellas: v),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Text('\$${linea.total.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Contador extends StatefulWidget {
  final String etiqueta;
  final double valor;
  final double? max;
  final ValueChanged<double> onChanged;
  const _Contador({required this.etiqueta, required this.valor, required this.onChanged, this.max});

  @override
  State<_Contador> createState() => _ContadorState();
}

class _ContadorState extends State<_Contador> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.valor));
  }

  @override
  void didUpdateWidget(covariant _Contador old) {
    super.didUpdateWidget(old);
    if (old.valor != widget.valor && _fmt(widget.valor) != _ctrl.text) {
      _ctrl.text = _fmt(widget.valor);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _set(double v) {
    if (v < 0) v = 0;
    if (widget.max != null && v > widget.max!) v = widget.max!;
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.etiqueta, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          height: 38,
          decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              _btn(Icons.remove_rounded, () => _set(widget.valor - 1)),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (t) => _set(double.tryParse(t) ?? 0),
                ),
              ),
              _btn(Icons.add_rounded, () => _set(widget.valor + 1)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(width: 34, child: Icon(icon, size: 18, color: AppTheme.primary)),
      );
}

class _BarraTotal extends StatelessWidget {
  final double total;
  final bool habilitado;
  final bool enviando;
  final bool editando;
  final VoidCallback onEnviar;
  const _BarraTotal({required this.total, required this.habilitado, required this.enviando, required this.onEnviar, this.editando = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              Text('\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.accent, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: habilitado ? onEnviar : null,
              icon: enviando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(editando ? Icons.save_rounded : Icons.send_rounded),
              label: Text(enviando ? 'Enviando...' : (editando ? 'Guardar cambios' : 'Enviar pedido')),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== SELECTOR DE CLIENTE ====================

class _SeleccionarClienteScreen extends StatefulWidget {
  const _SeleccionarClienteScreen();
  @override
  State<_SeleccionarClienteScreen> createState() => _SeleccionarClienteScreenState();
}

class _SeleccionarClienteScreenState extends State<_SeleccionarClienteScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<ClientesProvider>();
      if (p.clientes.isEmpty) p.cargarClientes();
    });
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<ClientesProvider>().cargarClientes(buscar: q.isEmpty ? null : q);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Seleccionar cliente')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onSearch,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre, cédula o código...',
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textSecondary),
              ),
            ),
          ),
          Expanded(
            child: Consumer<ClientesProvider>(
              builder: (context, p, _) {
                if (p.estaCargandoLista && p.clientes.isEmpty) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                }
                if (p.clientes.isEmpty) {
                  return const Center(child: Text('Sin resultados', style: TextStyle(color: AppTheme.textSecondary)));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: p.clientes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final c = p.clientes[i];
                    return ListTile(
                      tileColor: AppTheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text(c.nombreCompleto, style: const TextStyle(color: AppTheme.textPrimary), overflow: TextOverflow.ellipsis),
                      subtitle: Text(c.cedulaCompleta, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== SELECTOR DE PRODUCTO ====================

class _SeleccionarProductoScreen extends StatefulWidget {
  const _SeleccionarProductoScreen();
  @override
  State<_SeleccionarProductoScreen> createState() => _SeleccionarProductoScreenState();
}

class _SeleccionarProductoScreenState extends State<_SeleccionarProductoScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<ItemsProvider>();
      if (p.items.isEmpty) p.cargarItems();
    });
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<ItemsProvider>().cargarItems(buscar: q.isEmpty ? null : q);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Agregar producto')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onSearch,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Buscar por descripción o código...',
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textSecondary),
              ),
            ),
          ),
          Expanded(
            child: Consumer<ItemsProvider>(
              builder: (context, p, _) {
                if (p.estaCargandoLista && p.items.isEmpty) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                }
                final items = p.items.where((i) => i.dolPre > 0).toList();
                if (items.isEmpty) {
                  return const Center(child: Text('Sin resultados', style: TextStyle(color: AppTheme.textSecondary)));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final it = items[i];
                    return ListTile(
                      tileColor: AppTheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text(it.desitems, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        _descripcionProducto(it),
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text('\$${it.dolPre.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
                      onTap: () => Navigator.pop(context, it),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Ficha corta del producto: código, línea, presentación y tamaño de caja.
/// Sirve para distinguir productos con el mismo nombre (varias COCA COLA).
String _descripcionProducto(Item it) {
  final partes = <String>[it.coditems];
  if (it.nombreLinea.trim().isNotEmpty) partes.add(it.nombreLinea.trim());
  if (it.nombrePresentacion.trim().isNotEmpty) partes.add(it.nombrePresentacion.trim());
  if (it.cantunidad > 1) partes.add('caja de ${it.cantunidad.toStringAsFixed(0)}');
  return partes.join(' · ');
}